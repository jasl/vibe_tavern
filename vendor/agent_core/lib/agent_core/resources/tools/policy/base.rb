# frozen_string_literal: true

module AgentCore
  module Resources
    module Tools
      module Policy
        # Abstract base class for tool access policies.
        #
        # Policies control which tools are visible to the LLM and whether
        # specific tool calls are authorized. The app implements policies
        # based on its authorization model.
        class Base
          # Filter the list of tool definitions before sending to the LLM.
          #
          # @param tools [Array<Hash>] Tool definitions
          # @param context [AgentCore::ExecutionContext] Execution context
          # @return [Array<Hash>] Filtered tool definitions
          def filter(tools:, context:)
            tools # Default: no filtering
          end

          # Authorize a specific tool call.
          #
          # @param name [String] Executed tool name (resolved name that will actually be executed)
          # @param arguments [Hash] Tool arguments
          # @param context [AgentCore::ExecutionContext] Execution context
          # @return [Decision]
          def authorize(name:, arguments: {}, context:)
            Decision.allow # Default: allow all
          end
        end

        # The result of a policy authorization check.
        class Decision
          OUTCOMES = %i[allow deny confirm].freeze

          attr_reader :outcome, :reason

          def initialize(outcome:, reason: nil)
            unless OUTCOMES.include?(outcome)
              raise ArgumentError, "Invalid outcome: #{outcome}. Must be one of: #{OUTCOMES.join(", ")}"
            end
            @outcome = outcome
            @reason = reason
          end

          def allowed? = outcome == :allow
          def denied? = outcome == :deny
          def requires_confirmation? = outcome == :confirm

          def self.allow(reason: nil)
            new(outcome: :allow, reason: reason)
          end

          def self.deny(reason:)
            new(outcome: :deny, reason: reason)
          end

          def self.confirm(reason:)
            new(outcome: :confirm, reason: reason)
          end
        end
      end
    end
  end
end
