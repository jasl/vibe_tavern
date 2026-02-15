# frozen_string_literal: true

module AgentCore
  module Observability
    module Adapters
      # Instrumenter adapter for ActiveSupport::Notifications.
      #
      # Soft dependency: ActiveSupport is only required when the default notifier
      # is used. Apps can also inject any notifier responding to #instrument.
      class ActiveSupportNotificationsInstrumenter < Instrumenter
        def initialize(notifier: nil)
          @notifier = notifier || default_notifier
          return if @notifier&.respond_to?(:instrument)

          raise ArgumentError, "notifier must respond to #instrument (ActiveSupport not available?)"
        end

        def instrument(name, payload = {})
          event_name = name.to_s
          raise ArgumentError, "name is required" if event_name.strip.empty?

          data = payload.is_a?(Hash) ? payload : {}
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          ran = false
          result = nil
          block_error = nil

          begin
            @notifier.instrument(event_name, data) do
              begin
                ran = true
                result = yield if block_given?
              rescue StandardError => e
                block_error = e
                data[:error] ||= { class: e.class.name, message: e.message.to_s }
                raise
              ensure
                duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
                data[:duration_ms] ||= duration_ms
              end
              result
            end
          rescue StandardError
            raise block_error if block_error
            return result if ran

            return super(event_name, data) { yield if block_given? }
          end

          result
        end

        def _publish(name, payload)
          event_name = name.to_s
          return nil if event_name.strip.empty?

          data = payload.is_a?(Hash) ? payload : {}
          data[:duration_ms] ||= 0.0
          @notifier.instrument(event_name, data) { }
          nil
        end

        private

        def default_notifier
          require "active_support/notifications"
          ActiveSupport::Notifications
        rescue LoadError
          nil
        end
      end
    end
  end
end
