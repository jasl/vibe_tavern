# frozen_string_literal: true

require_relative "trace"

module TavernKit
  class PromptBuilder
    # Simple callable interface (Proc-compatible) for debug instrumentation.
    module Instrumenter
      class Base
        # @param event [Symbol] event type
        # @param payload [Hash] event-specific data (symbol keys)
        def call(event, **payload) = raise NotImplementedError
      end

      # Trace-collecting instrumenter for debugging.
      #
      # Event contract:
      # - :step_start (name:)
      # - :step_finish (name:, stats: {})
      # - :step_error (name:, error:)
      # - :warning (message:, step: optional)
      # - :stat (key:, value:, step: optional)
      class TraceCollector < Base
        Frame = Data.define(:name, :started_at, :warnings, :stats)

        attr_reader :steps, :warnings

        def initialize(clock: Process::CLOCK_MONOTONIC)
          @clock = clock
          @started_at = Time.now
          @frames = []
          @steps = []
          @warnings = []
        end

        def call(event, **payload)
          case event
          when :step_start
            assert_allowed_keys!(payload, %i[name])
            name = payload.fetch(:name)
            @frames << Frame.new(
              name: name,
              started_at: Process.clock_gettime(@clock),
              warnings: [],
              stats: {},
            )
          when :step_finish
            assert_allowed_keys!(payload, %i[name stats])
            finish_step(payload.fetch(:name), stats: payload[:stats])
          when :step_error
            assert_allowed_keys!(payload, %i[name error])
            finish_step(payload.fetch(:name), error: payload[:error])
          when :warning
            assert_allowed_keys!(payload, %i[message step])
            message = payload[:message].to_s
            @warnings << message

            step_name = payload[:step]
            frame = find_frame(step_name) || @frames.last
            frame&.warnings&.<< message
          when :stat
            assert_allowed_keys!(payload, %i[key value step])
            key = payload[:key]
            value = payload[:value]
            return nil unless key

            step_name = payload[:step]
            frame = find_frame(step_name) || @frames.last
            frame&.stats&.[]= key.to_sym, value
          end

          nil
        end

        def to_trace(fingerprint:)
          Trace.new(
            steps: @steps.dup.freeze,
            fingerprint: fingerprint.to_s,
            started_at: @started_at,
            finished_at: Time.now,
            total_warnings: @warnings.dup.freeze,
          )
        end

        private

        def finish_step(name, stats: nil, error: nil)
          frame = @frames.last
          raise ArgumentError, "Instrumentation mismatch: missing step_start for #{name.inspect}" unless frame
          raise ArgumentError, "Instrumentation mismatch: expected #{frame.name.inspect}, got #{name.inspect}" unless frame.name == name

          frame = @frames.pop

          duration_ms = (Process.clock_gettime(@clock) - frame.started_at) * 1000

          step_stats = frame.stats.dup
          step_stats.merge!(stats) if stats.is_a?(Hash)
          step_stats[:error] = error.class.name if error

          step = TraceStep.new(
            name: frame.name,
            duration_ms: duration_ms,
            stats: step_stats.freeze,
            warnings: frame.warnings.dup.freeze,
          )

          # Step events are nested (Rack-style), so finish order is the
          # reverse of execution order. Unshift to keep steps ordered as the
          # pipeline ran (outer -> inner).
          @steps.unshift(step)

          nil
        end

        def find_frame(name)
          return nil unless name

          @frames.reverse.find { |frame| frame.name == name }
        end

        def assert_allowed_keys!(payload, allowed)
          extra = payload.keys - allowed
          return nil if extra.empty?

          raise ArgumentError, "Unknown instrumentation payload keys: #{extra.inspect}"
        end
      end
    end
  end
end
