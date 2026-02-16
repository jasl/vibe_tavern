# frozen_string_literal: true

module AgentCore
  module Resources
    module PromptInjections
      module TextStore
        class InMemory < Base
          def initialize(values = {})
            @values = values.is_a?(Hash) ? values.dup : {}
          end

          def fetch(key:)
            @values[key] || @values[key.to_s] || @values[key.to_sym]
          end
        end
      end
    end
  end
end
