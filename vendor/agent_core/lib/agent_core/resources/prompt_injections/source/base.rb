# frozen_string_literal: true

module AgentCore
  module Resources
    module PromptInjections
      module Source
        class Base
          # @return [Array<PromptInjections::Item>]
          def items(agent:, user_message:, execution_context:, prompt_mode:)
            raise AgentCore::NotImplementedError, "#{self.class}#items must be implemented"
          end
        end
      end
    end
  end
end
