# frozen_string_literal: true

module TavernKit
  module RisuAI
    module TemplateCards
      module_function

      # Convert a SillyTavern "STCHAT" preset JSON into a RisuAI promptTemplate.
      #
      # Characterization source:
      # resources/Risuai/src/ts/process/prompt.ts (stChatConvert)
      def st_chat_convert(preset_hash)
        pre = TavernKit::Utils.deep_stringify_keys(preset_hash.is_a?(Hash) ? preset_hash : {})
        prompts = Array(pre["prompts"]).select { |p| p.is_a?(Hash) }

        order = Array(pre.dig("prompt_order", 0, "order")).select { |o| o.is_a?(Hash) }

        find_prompt = lambda do |identifier|
          prompts.find { |p| p["identifier"].to_s == identifier.to_s }
        end

        template = []

        order.each do |entry|
          enabled = entry.key?("enabled") ? TavernKit::Coerce.bool(entry["enabled"], default: false) : true
          next unless enabled

          p = find_prompt.call(entry["identifier"])
          next unless p

          identifier = p["identifier"].to_s
          content = p["content"].to_s
          role = p["role"].to_s
          role = "system" if role.empty?

          case identifier
          when "main"
            template << { "type" => "plain", "type2" => "main", "text" => content, "role" => role }
          when "jailbreak", "nsfw"
            template << { "type" => "jailbreak", "type2" => "normal", "text" => content, "role" => role }
          when "dialogueExamples", "charPersonality", "scenario"
            next
          when "chatHistory"
            template << { "type" => "chat", "rangeStart" => 0, "rangeEnd" => "end" }
          when "worldInfoBefore"
            template << { "type" => "lorebook" }
          when "worldInfoAfter"
            next
          when "charDescription"
            template << { "type" => "description" }
          when "personaDescription"
            template << { "type" => "persona" }
          else
            template << { "type" => "plain", "type2" => "normal", "text" => content, "role" => role }
          end
        end

        assistant_prefill = pre["assistant_prefill"]
        if assistant_prefill && !assistant_prefill.to_s.empty?
          template << { "type" => "postEverything" }
          template << {
            "type" => "plain",
            "type2" => "main",
            "text" => "{{#if {{prefill_supported}}}}#{assistant_prefill}{{/if}}",
            "role" => "bot",
          }
        end

        template
      end
    end
  end
end
