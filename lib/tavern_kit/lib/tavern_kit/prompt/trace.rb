# frozen_string_literal: true

module TavernKit
  module Prompt
    # Per-stage trace record.
    TraceStage = Data.define(
      :name,        # Symbol - middleware/stage name
      :duration_ms, # Float - execution time
      :stats,       # Hash - stage-specific counters (symbol keys)
      :warnings     # Array<String> - warnings emitted during this stage
    )

    # Complete pipeline trace.
    Trace = Data.define(
      :stages,        # Array<TraceStage>
      :fingerprint,   # String - stable fingerprint for caching/debugging
      :started_at,    # Time
      :finished_at,   # Time
      :total_warnings # Array<String>
    ) do
      def duration_ms = (finished_at - started_at) * 1000

      def success?
        stages.none? { |stage| stage.stats.key?(:error) }
      end
    end

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
      # - :middleware_start (name:)
      # - :middleware_finish (name:, stats: {})
      # - :middleware_error (name:, error:)
      # - :warning (message:, stage: optional)
      # - :stat (key:, value:, stage: optional)
      class TraceCollector < Base
        Frame = Data.define(:name, :started_at, :warnings, :stats)

        attr_reader :stages, :warnings

        def initialize(clock: Process::CLOCK_MONOTONIC)
          @clock = clock
          @started_at = Time.now
          @frames = []
          @stages = []
          @warnings = []
        end

        def call(event, **payload)
          case event
          when :middleware_start
            name = payload.fetch(:name)
            @frames << Frame.new(
              name: name,
              started_at: Process.clock_gettime(@clock),
              warnings: [],
              stats: {},
            )
          when :middleware_finish
            finish_stage(payload.fetch(:name), stats: payload[:stats])
          when :middleware_error
            finish_stage(payload.fetch(:name), error: payload[:error])
          when :warning
            message = payload[:message].to_s
            @warnings << message

            stage_name = payload[:stage]
            frame = find_frame(stage_name) || @frames.last
            frame&.warnings&.<< message
          when :stat
            key = payload[:key]
            value = payload[:value]
            return nil unless key

            stage_name = payload[:stage]
            frame = find_frame(stage_name) || @frames.last
            frame&.stats&.[]= key.to_sym, value
          end

          nil
        end

        def to_trace(fingerprint:)
          Trace.new(
            stages: @stages.freeze,
            fingerprint: fingerprint.to_s,
            started_at: @started_at,
            finished_at: Time.now,
            total_warnings: @warnings.freeze,
          )
        end

        private

        def finish_stage(name, stats: nil, error: nil)
          frame = @frames.pop
          return nil unless frame

          duration_ms = (Process.clock_gettime(@clock) - frame.started_at) * 1000

          stage_stats = frame.stats.dup
          stage_stats.merge!(stats) if stats.is_a?(Hash)
          stage_stats[:error] = error.class.name if error

          stage = TraceStage.new(
            name: frame.name,
            duration_ms: duration_ms,
            stats: stage_stats.freeze,
            warnings: frame.warnings.dup.freeze,
          )

          # Middleware events are nested (Rack-style), so finish order is the
          # reverse of execution order. Unshift to keep stages ordered as the
          # pipeline ran (outer -> inner).
          @stages.unshift(stage)

          nil
        end

        def find_frame(name)
          return nil unless name

          @frames.reverse.find { |frame| frame.name == name }
        end
      end
    end
  end
end
