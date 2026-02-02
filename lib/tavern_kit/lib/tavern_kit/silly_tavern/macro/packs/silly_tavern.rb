# frozen_string_literal: true

require_relative "silly_tavern/core_macros"
require_relative "silly_tavern/chat_macros"
require_relative "silly_tavern/env_macros"
require_relative "silly_tavern/instruct_macros"
require_relative "silly_tavern/state_macros"
require_relative "silly_tavern/time_macros"
require_relative "silly_tavern/variable_macros"

module TavernKit
  module SillyTavern
    module Macro
      module Packs
        # Built-in macro pack aiming for SillyTavern parity.
        #
        # This file intentionally starts small and grows with tests. Avoid adding
        # macros without a corresponding spec/characterization test.
        module SillyTavern
          def self.default_registry
            @default_registry ||= begin
              registry = TavernKit::SillyTavern::Macro::Registry.new
              register(registry)
              registry
            end
          end

          def self.register(registry)
            register_core_macros(registry)
            register_chat_macros(registry)
            register_env_macros(registry)
            register_instruct_macros(registry)
            register_state_macros(registry)
            register_time_macros(registry)
            register_variable_macros(registry)
            registry
          end
        end
      end
    end
  end
end
