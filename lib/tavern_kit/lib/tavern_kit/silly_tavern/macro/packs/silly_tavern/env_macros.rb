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

            registry.register("groupNotMuted") do |inv|
              attrs = inv.environment.respond_to?(:platform_attrs) ? inv.environment.platform_attrs : {}
              value = TavernKit::Utils::HashAccessor.wrap(attrs).fetch(:group_not_muted, :groupNotMuted, default: nil)
              value.nil? ? inv.environment.group_name.to_s : value.to_s
            end

            registry.register("notChar") do |inv|
              attrs = inv.environment.respond_to?(:platform_attrs) ? inv.environment.platform_attrs : {}
              TavernKit::Utils::HashAccessor.wrap(attrs).fetch(:not_char, :notChar, default: "").to_s
            end

            registry.register("charPrompt") do |inv|
              char = inv.environment.respond_to?(:character) ? inv.environment.character : nil
              char.respond_to?(:data) ? char.data.system_prompt.to_s : ""
            end

            registry.register("charInstruction") do |inv|
              char = inv.environment.respond_to?(:character) ? inv.environment.character : nil
              char.respond_to?(:data) ? char.data.post_history_instructions.to_s : ""
            end

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

            registry.register("mesExamples") do |inv|
              raw = inv.resolve("{{mesExamplesRaw}}").to_s
              next "" if raw.strip.empty?

              env = inv.environment
              attrs = env.respond_to?(:platform_attrs) ? env.platform_attrs : {}
              ha = TavernKit::Utils::HashAccessor.wrap(attrs)

              main_api = ha.fetch(:main_api, :mainApi, default: nil)
              is_instruct = ha.bool(:is_instruct, :isInstruct, default: false)
              example_separator = ha.fetch(:example_separator, :exampleSeparator, default: nil)

              TavernKit::SillyTavern::ExamplesParser.format(
                raw,
                example_separator: example_separator,
                is_instruct: is_instruct,
                main_api: main_api,
              )
            end

            registry.register("charDepthPrompt") do |inv|
              char = inv.environment.respond_to?(:character) ? inv.environment.character : nil
              ext = char.respond_to?(:data) ? char.data.extensions : {}

              prompt = TavernKit::Utils::HashAccessor.wrap(ext).dig(:depth_prompt, :prompt)
              prompt.to_s
            end

            registry.register("charCreatorNotes") do |inv|
              char = inv.environment.respond_to?(:character) ? inv.environment.character : nil
              char.respond_to?(:data) ? char.data.creator_notes.to_s : ""
            end
            registry.register_alias("charCreatorNotes", "creatorNotes")

            registry.register("charVersion") do |inv|
              char = inv.environment.respond_to?(:character) ? inv.environment.character : nil
              char.respond_to?(:data) ? char.data.character_version.to_s : ""
            end
            registry.register_alias("charVersion", "version", visible: false)
            registry.register_alias("charVersion", "char_version", visible: false)

            registry.register("model") do |inv|
              attrs = inv.environment.respond_to?(:platform_attrs) ? inv.environment.platform_attrs : {}
              ha = TavernKit::Utils::HashAccessor.wrap(attrs)
              ha.fetch(:model, default: nil) || ha.dig(:system, :model) || ""
            end

            registry.register("isMobile") do |inv|
              attrs = inv.environment.respond_to?(:platform_attrs) ? inv.environment.platform_attrs : {}
              mobile = TavernKit::Utils::HashAccessor.wrap(attrs).bool(:is_mobile, :isMobile, default: false)
              mobile ? "true" : "false"
            end
          end

          private_class_method :register_env_macros
        end
      end
    end
  end
end
