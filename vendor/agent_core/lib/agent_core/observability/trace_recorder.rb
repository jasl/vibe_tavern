# frozen_string_literal: true

module AgentCore
  module Observability
    # In-memory recorder for instrumented events.
    #
    # Useful for tests, audits, and debugging. Produces a JSON-serializable trace.
    class TraceRecorder < Instrumenter
      CAPTURE_LEVELS = %i[none safe full].freeze

      DEFAULT_MAX_STRING_BYTES = 10_000
      DEFAULT_MAX_DEPTH = 10

      DEFAULT_SAFE_REDACT_KEYS = %w[
        content
        body
        prompt
        messages
        tools
        arguments
        result
        raw
        request
        response
      ].freeze

      attr_reader :events

      # @param capture [Symbol] :none, :safe, :full
      # @param max_string_bytes [Integer] truncate long strings
      # @param max_depth [Integer] recursion guard for deep objects
      # @param redactor [#call, nil] custom payload transformer: (name, payload_hash) -> Hash
      def initialize(capture: :safe, max_string_bytes: DEFAULT_MAX_STRING_BYTES, max_depth: DEFAULT_MAX_DEPTH, redactor: nil)
        unless CAPTURE_LEVELS.include?(capture)
          raise ArgumentError, "capture must be one of: #{CAPTURE_LEVELS.join(", ")}"
        end

        @capture = capture
        @max_string_bytes = Integer(max_string_bytes)
        raise ArgumentError, "max_string_bytes must be positive" if @max_string_bytes <= 0

        @max_depth = Integer(max_depth)
        raise ArgumentError, "max_depth must be positive" if @max_depth <= 0

        if redactor && !redactor.respond_to?(:call)
          raise ArgumentError, "redactor must respond to #call"
        end
        @redactor = redactor

        @events = []
        @mutex = Mutex.new
      end

      def _publish(name, payload)
        event_name = name.to_s
        data = payload.is_a?(Hash) ? payload.dup : {}
        recorded = record_payload(event_name, data)

        @mutex.synchronize do
          @events << { name: event_name, at: Time.now, payload: recorded }.freeze
        end

        nil
      end

      # JSON-friendly trace structure.
      def trace
        @mutex.synchronize { @events.dup }
      end

      private

      def record_payload(name, payload)
        base =
          case @capture
          when :none
            keep_minimal(payload)
          when :safe
            safe = deep_sanitize(payload, depth: 0)
            safe = safe_redact_keys(safe)
            safe
          when :full
            deep_sanitize(payload, depth: 0)
          end

        base = @redactor.call(name, base) if @redactor
        base.is_a?(Hash) ? base : {}
      rescue StandardError
        {}
      end

      def keep_minimal(payload)
        out = {}
        out[:duration_ms] = payload[:duration_ms] if payload.key?(:duration_ms)
        out[:error] = payload[:error] if payload.key?(:error)
        out
      end

      def safe_redact_keys(hash)
        return {} unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(k, v), out|
          key = k.to_s
          if DEFAULT_SAFE_REDACT_KEYS.include?(key)
            out[key] = "[redacted]"
          else
            out[key] = v
          end
        end
      end

      def deep_sanitize(value, depth:)
        return "[max_depth]" if depth >= @max_depth

        case value
        when nil, true, false, Integer, Float
          value
        when Symbol
          value.to_s
        when String
          truncate_string(value)
        when Array
          value.map { |v| deep_sanitize(v, depth: depth + 1) }
        when Hash
          value.each_with_object({}) do |(k, v), out|
            key = k.is_a?(Symbol) ? k.to_s : k.to_s
            out[key] = deep_sanitize(v, depth: depth + 1)
          end
        else
          truncate_string(value.to_s)
        end
      end

      def truncate_string(str)
        s = str.to_s
        return s if s.bytesize <= @max_string_bytes

        suffix = "...[truncated]"
        head = s.byteslice(0, @max_string_bytes)
        head = head.to_s
        head = head.dup.force_encoding(Encoding::UTF_8)
        head = head.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD") unless head.valid_encoding?

        room = @max_string_bytes - suffix.bytesize
        return suffix if room <= 0

        head.byteslice(0, room).to_s + suffix
      rescue StandardError
        ""
      end
    end
  end
end
