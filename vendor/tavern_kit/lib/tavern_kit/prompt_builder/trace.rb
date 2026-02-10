# frozen_string_literal: true

module TavernKit
  class PromptBuilder
    # Per-step trace record.
    TraceStep = Data.define(
      :name,        # Symbol - step name
      :duration_ms, # Float - execution time
      :stats,       # Hash - step-specific counters (symbol keys)
      :warnings     # Array<String> - warnings emitted during this step
    )

    # Complete pipeline trace.
    Trace = Data.define(
      :steps,         # Array<TraceStep>
      :fingerprint,   # String - stable fingerprint for caching/debugging
      :started_at,    # Time
      :finished_at,   # Time
      :total_warnings # Array<String>
    ) do
      def duration_ms = (finished_at - started_at) * 1000

      def success?
        steps.none? { |step| step.stats.key?(:error) }
      end
    end
  end
end
