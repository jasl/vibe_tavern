# frozen_string_literal: true

module AgentCore
  module Observability
    module Adapters
      # Instrumenter adapter for OpenTelemetry.
      #
      # Soft dependency: OpenTelemetry is only required when the default tracer
      # is used. Apps can also inject any tracer responding to #in_span.
      class OpenTelemetryInstrumenter < Instrumenter
        DEFAULT_MAX_ATTRIBUTE_BYTES = 10_000

        def initialize(tracer: nil, max_attribute_bytes: DEFAULT_MAX_ATTRIBUTE_BYTES)
          @max_attribute_bytes = Integer(max_attribute_bytes)
          raise ArgumentError, "max_attribute_bytes must be positive" if @max_attribute_bytes <= 0

          @tracer = tracer || default_tracer
          return if @tracer&.respond_to?(:in_span)

          raise ArgumentError, "tracer must respond to #in_span (OpenTelemetry not available?)"
        end

        def instrument(name, payload = {})
          event_name = name.to_s
          raise ArgumentError, "name is required" if event_name.strip.empty?

          data = payload.is_a?(Hash) ? payload : {}
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          attributes = otel_attributes(data)

          @tracer.in_span(event_name, attributes: attributes) do |span|
            begin
              yield if block_given?
            rescue StandardError => e
              data[:error] ||= { class: e.class.name, message: e.message.to_s }
              record_exception(span, e)
              raise
            ensure
              duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
              data[:duration_ms] ||= duration_ms
              span.set_attribute("duration_ms", data[:duration_ms]) if span.respond_to?(:set_attribute)
              if (err = data[:error]).is_a?(Hash)
                span.set_attribute("error.class", err[:class].to_s) if span.respond_to?(:set_attribute) && err[:class]
                span.set_attribute("error.message", err[:message].to_s) if span.respond_to?(:set_attribute) && err[:message]
              end
            end
          end
        end

        def publish(name, payload)
          instrument(name, payload) { }
          nil
        end

        private

        def default_tracer
          require "opentelemetry-api"
          OpenTelemetry.tracer_provider.tracer("agent_core", AgentCore::VERSION)
        rescue LoadError
          nil
        end

        def record_exception(span, error)
          return unless span

          span.record_exception(error) if span.respond_to?(:record_exception)

          if span.respond_to?(:status=) && defined?(::OpenTelemetry::Trace::Status)
            span.status = ::OpenTelemetry::Trace::Status.error(error.message.to_s)
          end
        rescue StandardError
          nil
        end

        def otel_attributes(payload)
          out = {}

          payload.each do |k, v|
            key = k.is_a?(Symbol) ? k.to_s : k.to_s
            next if key.empty?

            out[key] = otel_value(v)
          end

          out
        rescue StandardError
          {}
        end

        def otel_value(value)
          case value
          when nil, true, false, Integer, Float, String
            value
          when Symbol
            value.to_s
          when Array
            value.map { |v| otel_value(v) }
          when Hash
            truncate(try_json(value))
          else
            truncate(value.to_s)
          end
        end

        def try_json(value)
          require "json"
          JSON.generate(value)
        rescue StandardError
          value.to_s
        end

        def truncate(str)
          AgentCore::Utils.truncate_utf8_bytes(str, max_bytes: @max_attribute_bytes)
        rescue StandardError
          ""
        end
      end
    end
  end
end
