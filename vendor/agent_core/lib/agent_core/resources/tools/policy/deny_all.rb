# frozen_string_literal: true

module AgentCore
  module Resources
    module Tools
      module Policy
        # Denies all tool visibility and execution.
        #
        # Used as the default policy to keep AgentCore safe-by-default.
        class DenyAll < Base
          def filter(tools:, context:)
            []
          end

          def authorize(name:, arguments:, context:)
            Decision.deny(reason: "tool access denied by default")
          end
        end
      end
    end
  end
end
