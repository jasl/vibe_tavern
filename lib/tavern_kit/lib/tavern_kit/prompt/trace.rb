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
  end
end
