# frozen_string_literal: true

module AgentCore
  module Observability
    # Library-agnostic instrumentation interface.
    #
    # AgentCore uses this to emit timing + error metadata for:
    # - run / turn
    # - LLM calls
    # - tool authorization + execution
    #
    # Implementations can forward data to any backend (logs, OpenTelemetry,
    # ActiveSupport::Notifications, etc.).
    class Instrumenter
      # Instrument a named operation.
      #
      # Publishes a single event after the block completes, with:
      # - duration_ms
      # - error (when raised)
      #
      # The exception is re-raised after publishing.
      #
      # @param name [String] event/span name
      # @param payload [Hash] structured metadata
      def instrument(name, payload = {})
        event_name = name.to_s
        raise ArgumentError, "name is required" if event_name.strip.empty?

        data = payload.is_a?(Hash) ? payload : {}
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          yield if block_given?
        rescue StandardError => e
          data[:error] ||= { class: e.class.name, message: e.message.to_s }
          raise
        ensure
          duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
          data[:duration_ms] ||= duration_ms
          publish(event_name, data.dup)
        end
      end

      # Publish an event to the backend (best-effort).
      #
      # This method must never raise (observability should not interfere with
      # the main execution flow). Implementations should override #_publish.
      #
      # @param name [String]
      # @param payload [Hash]
      # @return [nil]
      def publish(name, payload)
        event_name = name.to_s
        return nil if event_name.strip.empty?

        data = payload.is_a?(Hash) ? payload : {}
        _publish(event_name, data)
        nil
      rescue StandardError
        nil
      end

      # Implementation hook for subclasses.
      #
      # @api private
      def _publish(_name, _payload)
        raise AgentCore::NotImplementedError, "#{self.class}#_publish must be implemented"
      end
    end
  end
end
