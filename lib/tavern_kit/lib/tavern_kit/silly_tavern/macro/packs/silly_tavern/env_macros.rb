# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      module Packs
        module SillyTavern
          def self.register_env_macros(registry)
            # Note: ST's {{original}} expands at most once per evaluation.
            # The V2 engine enforces this at the engine level.
            registry.register("original") do |inv|
              inv.environment.respond_to?(:original) ? inv.environment.original.to_s : ""
            end

            registry.register("user") { |inv| inv.environment.user_name.to_s }
            registry.register("char") { |inv| inv.environment.character_name.to_s }

            registry.register("group") { |inv| inv.environment.group_name.to_s }
            registry.register_alias("group", "charIfNotGroup", visible: false)

            registry.register("persona") do |inv|
              user = inv.environment.respond_to?(:user) ? inv.environment.user : nil
              user.respond_to?(:persona_text) ? user.persona_text.to_s : ""
            end

            registry.register("charDescription") do |inv|
              char = inv.environment.respond_to?(:character) ? inv.environment.character : nil
              char.respond_to?(:data) ? char.data.description.to_s : ""
            end
            registry.register_alias("charDescription", "description")

            registry.register("charPersonality") do |inv|
              char = inv.environment.respond_to?(:character) ? inv.environment.character : nil
              char.respond_to?(:data) ? char.data.personality.to_s : ""
            end
            registry.register_alias("charPersonality", "personality")

            registry.register("charScenario") do |inv|
              char = inv.environment.respond_to?(:character) ? inv.environment.character : nil
              char.respond_to?(:data) ? char.data.scenario.to_s : ""
            end
            registry.register_alias("charScenario", "scenario")

            registry.register("mesExamplesRaw") do |inv|
              char = inv.environment.respond_to?(:character) ? inv.environment.character : nil
              char.respond_to?(:data) ? char.data.mes_example.to_s : ""
            end
          end

          private_class_method :register_env_macros
        end
      end
    end
  end
end
