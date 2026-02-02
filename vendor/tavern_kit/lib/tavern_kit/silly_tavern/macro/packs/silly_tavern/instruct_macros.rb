# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      module Packs
        module SillyTavern
          def self.register_instruct_macros(registry)
            register_instruct_simple(registry, "instructStoryStringPrefix") { |i| i.story_string_prefix }
            register_instruct_simple(registry, "instructStoryStringSuffix") { |i| i.story_string_suffix }

            register_instruct_simple(registry, "instructUserPrefix") { |i| i.input_sequence }
            registry.register_alias("instructUserPrefix", "instructInput")

            register_instruct_simple(registry, "instructUserSuffix") { |i| i.input_suffix }

            register_instruct_simple(registry, "instructAssistantPrefix") { |i| i.output_sequence }
            registry.register_alias("instructAssistantPrefix", "instructOutput")

            register_instruct_simple(registry, "instructAssistantSuffix") { |i| i.output_suffix }
            registry.register_alias("instructAssistantSuffix", "instructSeparator")

            register_instruct_simple(registry, "instructSystemPrefix") { |i| i.system_sequence }
            register_instruct_simple(registry, "instructSystemSuffix") { |i| i.system_suffix }

            register_instruct_simple(registry, "instructFirstAssistantPrefix") { |i| fallback(i.first_output_sequence, i.output_sequence) }
            registry.register_alias("instructFirstAssistantPrefix", "instructFirstOutputPrefix")

            register_instruct_simple(registry, "instructLastAssistantPrefix") { |i| fallback(i.last_output_sequence, i.output_sequence) }
            registry.register_alias("instructLastAssistantPrefix", "instructLastOutputPrefix")

            register_instruct_simple(registry, "instructStop") { |i| i.stop_sequence }
            register_instruct_simple(registry, "instructUserFiller") { |i| i.user_alignment_message }
            register_instruct_simple(registry, "instructSystemInstructionPrefix") { |i| i.last_system_sequence }

            register_instruct_simple(registry, "instructFirstUserPrefix") { |i| fallback(i.first_input_sequence, i.input_sequence) }
            registry.register_alias("instructFirstUserPrefix", "instructFirstInput")

            register_instruct_simple(registry, "instructLastUserPrefix") { |i| fallback(i.last_input_sequence, i.input_sequence) }
            registry.register_alias("instructLastUserPrefix", "instructLastInput")

            registry.register("defaultSystemPrompt") { |inv| default_system_prompt(inv) }
            registry.register_alias("defaultSystemPrompt", "instructSystem")
            registry.register_alias("defaultSystemPrompt", "instructSystemPrompt")

            registry.register("systemPrompt") { |inv| system_prompt(inv) }

            registry.register("exampleSeparator") { |inv| context_value(inv, :example_separator) }
            registry.register_alias("exampleSeparator", "chatSeparator")
            registry.register("chatStart") { |inv| context_value(inv, :chat_start) }
          end

          def self.register_instruct_simple(registry, name, &block)
            registry.register(name) do |inv|
              instruct = instruct_from(inv)
              next "" unless instruct&.respond_to?(:enabled?) && instruct.enabled?

              value = block.call(instruct)
              value.to_s
            end
          end

          def self.instruct_from(inv)
            env = inv.environment
            attrs = env.respond_to?(:platform_attrs) ? env.platform_attrs : {}
            inst = TavernKit::Utils::HashAccessor.wrap(attrs).fetch(:instruct, default: nil)
            inst.respond_to?(:enabled?) ? inst : nil
          end

          def self.default_system_prompt(inv)
            env = inv.environment
            attrs = env.respond_to?(:platform_attrs) ? env.platform_attrs : {}
            ha = TavernKit::Utils::HashAccessor.wrap(attrs)

            enabled = ha.bool(:sysprompt_enabled, :system_prompt_enabled, default: false)
            return "" unless enabled

            ha.fetch(:sysprompt_content, :system_prompt_content, :default_system_prompt, default: "").to_s
          end

          def self.system_prompt(inv)
            env = inv.environment
            attrs = env.respond_to?(:platform_attrs) ? env.platform_attrs : {}
            ha = TavernKit::Utils::HashAccessor.wrap(attrs)

            enabled = ha.bool(:sysprompt_enabled, :system_prompt_enabled, default: false)
            return "" unless enabled

            prefer_char = ha.bool(:prefer_character_prompt, :preferCharacterPrompt, default: false)

            if prefer_char
              candidate = inv.resolve("{{charPrompt}}").to_s
              return candidate unless candidate.strip.empty?
            end

            default_system_prompt(inv)
          end

          def self.context_value(inv, key)
            env = inv.environment
            attrs = env.respond_to?(:platform_attrs) ? env.platform_attrs : {}
            ha = TavernKit::Utils::HashAccessor.wrap(attrs)

            context = ha.fetch(:context_template, :context, default: nil)

            value =
              if context.respond_to?(key)
                context.public_send(key)
              elsif context.is_a?(Hash)
                TavernKit::Utils::HashAccessor.wrap(context).fetch(key, default: nil)
              else
                nil
              end

            value = ha.fetch(key, default: nil) if value.nil?
            value.to_s
          end

          def self.fallback(primary, secondary)
            p = primary.to_s
            p.empty? ? secondary.to_s : p
          end

          private_class_method :context_value, :default_system_prompt, :fallback, :instruct_from, :register_instruct_macros,
            :register_instruct_simple, :system_prompt
        end
      end
    end
  end
end
