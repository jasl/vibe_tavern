# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolCalling
      module Policies
        Decision =
          Data.define(
            :outcome,
            :decision_id,
            :reason_codes,
            :message,
            :confirm,
          ) do
            OUTCOMES = %i[allow deny confirm].freeze

            def initialize(outcome:, decision_id: nil, reason_codes: nil, message: nil, confirm: nil)
              outcome = outcome.to_s.strip.downcase.tr("-", "_").to_sym
              raise ArgumentError, "outcome not supported: #{outcome.inspect}" unless OUTCOMES.include?(outcome)

              decision_id = decision_id&.to_s
              decision_id = nil if decision_id&.strip&.empty?

              reason_codes =
                Array(reason_codes)
                  .map { |v| v.to_s.strip }
                  .reject(&:empty?)
                  .uniq

              message = message&.to_s
              message = nil if message&.strip&.empty?

              confirm = confirm.is_a?(Hash) ? confirm : nil

              super(
                outcome: outcome,
                decision_id: decision_id,
                reason_codes: reason_codes,
                message: message,
                confirm: confirm,
              )
            end

            def self.allow(decision_id: nil, reason_codes: nil, message: nil)
              new(
                outcome: :allow,
                decision_id: decision_id,
                reason_codes: reason_codes,
                message: message,
                confirm: nil,
              )
            end

            def self.deny(decision_id: nil, reason_codes: nil, message: nil)
              new(
                outcome: :deny,
                decision_id: decision_id,
                reason_codes: reason_codes,
                message: message,
                confirm: nil,
              )
            end

            def self.confirm(decision_id: nil, reason_codes: nil, message: nil, confirm: nil)
              new(
                outcome: :confirm,
                decision_id: decision_id,
                reason_codes: reason_codes,
                message: message,
                confirm: confirm,
              )
            end
          end

        class ToolPolicy
          def filter_tools(tools:, context:, expose:)
            tools
          end

          def authorize_call(name:, args:, context:, tool_call_id:)
            Decision.allow
          end
        end

        class AllowAllPolicy < ToolPolicy
        end
      end
    end
  end
end
