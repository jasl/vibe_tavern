# frozen_string_literal: true

module AgentCore
  module Resources
    module PromptInjections
      module TextStore
        class Base
          def fetch(key:)
            raise AgentCore::NotImplementedError, "#{self.class}#fetch must be implemented"
          end
        end
      end
    end
  end
end
