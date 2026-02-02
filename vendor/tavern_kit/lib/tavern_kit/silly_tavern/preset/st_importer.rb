# frozen_string_literal: true

module TavernKit
  module SillyTavern
    class Preset
      # Responsible for importing SillyTavern chat completion preset JSON into a Preset.
      #
      # Hash-only: the caller is responsible for file I/O and `JSON.parse`.
      class StImporter
        # ST pinned prompt identifiers (Prompt Manager).
        #
        # Maps ST identifiers (often camelCase) to TavernKit canonical ids.
        ST_PINNED_IDS = {
          # Core prompts
          "main" => "main_prompt",
          "mainPrompt" => "main_prompt",
          "jailbreak" => "post_history_instructions",
          "postHistoryInstructions" => "post_history_instructions",

          # Character information
          "personaDescription" => "persona_description",
          "persona_description" => "persona_description",
          "charDescription" => "character_description",
          "character_description" => "character_description",
          "charPersonality" => "character_personality",
          "character_personality" => "character_personality",
          "scenario" => "scenario",

          # Auxiliary/NSFW prompts
          "nsfw" => "auxiliary_prompt",
          "auxiliaryPrompt" => "auxiliary_prompt",
          "auxiliary_prompt" => "auxiliary_prompt",
          "enhanceDefinitions" => "enhance_definitions",
          "enhance_definitions" => "enhance_definitions",

          # Chat related
          "dialogueExamples" => "chat_examples",
          "dialogue_examples" => "chat_examples",
          "chat_examples" => "chat_examples",
          "chatHistory" => "chat_history",
          "chat_history" => "chat_history",

          # World Info positions
          "worldInfoBefore" => "world_info_before_char_defs",
          "worldInfoAfter" => "world_info_after_char_defs",
          "world_info_before" => "world_info_before_char_defs",
          "world_info_after" => "world_info_after_char_defs",

          # Additional World Info positions (extended presets)
          "worldInfoBeforeExamples" => "world_info_before_example_messages",
          "worldInfoAfterExamples" => "world_info_after_example_messages",
          "world_info_before_examples" => "world_info_before_example_messages",
          "world_info_after_examples" => "world_info_after_example_messages",

          # Author's Note
          "authorsNote" => "authors_note",
          "authors_note" => "authors_note",
        }.freeze

        def initialize(hash)
          raise ArgumentError, "ST preset must be a Hash" unless hash.is_a?(Hash)

          @hash = Utils.deep_stringify_keys(hash)
        end

        def to_preset
          hash = @hash

          prompts_by_id = build_prompts_by_id(hash["prompts"])

          main_prompt = prompts_by_id.dig("main", "content").to_s
          main_prompt = Preset::DEFAULT_MAIN_PROMPT if main_prompt.strip.empty?

          post_history_instructions = prompts_by_id.dig("jailbreak", "content").to_s

          enhance_definitions = prompts_by_id.dig("enhanceDefinitions", "content")
          enhance_definitions = Preset::DEFAULT_ENHANCE_DEFINITIONS if enhance_definitions.nil? || enhance_definitions.to_s.strip.empty?

          auxiliary_prompt = prompts_by_id.dig("nsfw", "content").to_s

          prompt_entries = build_prompt_entries_from_st(hash)

          Preset.new(
            main_prompt: main_prompt,
            post_history_instructions: post_history_instructions,
            enhance_definitions: enhance_definitions,
            auxiliary_prompt: auxiliary_prompt,

            send_if_empty: hash["send_if_empty"].to_s,
            new_chat_prompt: hash["new_chat_prompt"] || Preset::DEFAULT_NEW_CHAT_PROMPT,
            new_group_chat_prompt: hash["new_group_chat_prompt"] || Preset::DEFAULT_NEW_GROUP_CHAT_PROMPT,
            new_example_chat_prompt: hash["new_example_chat_prompt"] || Preset::DEFAULT_NEW_EXAMPLE_CHAT_PROMPT,
            continue_nudge_prompt: hash["continue_nudge_prompt"] || Preset::DEFAULT_CONTINUE_NUDGE_PROMPT,
            group_nudge_prompt: hash["group_nudge_prompt"] || Preset::DEFAULT_GROUP_NUDGE_PROMPT,
            impersonation_prompt: hash["impersonation_prompt"] || Preset::DEFAULT_IMPERSONATION_PROMPT,
            assistant_prefill: hash["assistant_prefill"],
            assistant_impersonation: hash["assistant_impersonation"],

            use_sysprompt: Coerce.bool(hash["use_sysprompt"], default: false),
            squash_system_messages: Coerce.bool(hash["squash_system_messages"], default: false),
            names_behavior: Preset::NamesBehavior.coerce(hash["names_behavior"]),
            custom_prompt_post_processing: Utils.presence(hash["custom_prompt_post_processing"]),
            bias_preset_selected: Utils.presence(hash["bias_preset_selected"]),
            prompt_entries: prompt_entries,
            pinned_group_resolver: hash["pinned_group_resolver"],

            context_window_tokens: hash["openai_max_context"] || 4096,
            reserved_response_tokens: hash["openai_max_tokens"] || 300,
            message_token_overhead: (hash["message_token_overhead"] || 4),
            max_context_unlocked: Coerce.bool(hash["max_context_unlocked"], default: false),

            world_info_depth: hash["world_info_depth"],
            world_info_budget: hash["world_info_budget"],
            world_info_budget_cap: hash["world_info_budget_cap"] || 0,
            world_info_include_names: Coerce.bool(hash["world_info_include_names"], default: true),
            world_info_min_activations: hash["world_info_min_activations"] || 0,
            world_info_min_activations_depth_max: hash["world_info_min_activations_depth_max"] || 0,
            world_info_use_group_scoring: Coerce.bool(hash["world_info_use_group_scoring"], default: false),

            authors_note: hash["authors_note"].to_s,
            authors_note_frequency: hash["authors_note_frequency"] || 1,
            authors_note_position: hash["authors_note_position"] || Preset::DEFAULT_AUTHORS_NOTE_POSITION,
            authors_note_depth: hash.key?("authors_note_depth") ? hash["authors_note_depth"] : Preset::DEFAULT_AUTHORS_NOTE_DEPTH,
            authors_note_role: hash["authors_note_role"] || Preset::DEFAULT_AUTHORS_NOTE_ROLE,
            authors_note_allow_wi_scan: Coerce.bool(hash.fetch("allowWIScan", hash["authors_note_allow_wi_scan"]), default: false),

            wi_format: hash["wi_format"] || Preset::DEFAULT_WI_FORMAT,
            scenario_format: hash["scenario_format"] || Preset::DEFAULT_SCENARIO_FORMAT,
            personality_format: hash["personality_format"] || Preset::DEFAULT_PERSONALITY_FORMAT,

            temperature: coerce_float(hash, "temperature", "temp_openai", default: 1.0),
            top_p: coerce_float(hash, "top_p", "top_p_openai", default: 1.0),
            top_k: coerce_int(hash, "top_k", "top_k_openai", default: 0),
            top_a: coerce_float(hash, "top_a", "top_a_openai", default: 0.0),
            min_p: coerce_float(hash, "min_p", "min_p_openai", default: 0.0),
            frequency_penalty: coerce_float(hash, "frequency_penalty", "freq_pen_openai", default: 0.0),
            presence_penalty: coerce_float(hash, "presence_penalty", "pres_pen_openai", default: 0.0),
            repetition_penalty: coerce_float(hash, "repetition_penalty", "repetition_penalty_openai", default: 1.0),

            continue_prefill: Coerce.bool(hash["continue_prefill"], default: false),
            continue_postfix: coerce_st_continue_postfix(hash["continue_postfix"]) || " ",

            examples_behavior: hash["examples_behavior"] || :gradually_push_out,
            prefer_char_prompt: Coerce.bool(hash["prefer_character_prompt"], default: true),
            prefer_char_instructions: Coerce.bool(hash["prefer_character_jailbreak"], default: true),
            character_lore_insertion_strategy: hash["character_lore_insertion_strategy"] || :character_lore_first,

            custom_stopping_strings: hash["custom_stopping_strings"].to_s,
            custom_stopping_strings_macro: Coerce.bool(hash.fetch("custom_stopping_strings_macro", true), default: true),
            single_line: Coerce.bool(hash["single_line"], default: false),

            instruct: extract_instruct_settings(hash),
            context_template: extract_context_settings(hash),
          )
        end

        private

        def coerce_float(hash, *keys, default:)
          keys.each do |k|
            v = hash[k]
            return v.to_f unless v.nil?
          end
          default
        end

        def coerce_int(hash, *keys, default:)
          keys.each do |k|
            v = hash[k]
            return v.to_i unless v.nil?
          end
          default
        end

        def build_prompts_by_id(prompts)
          return {} unless prompts.is_a?(Array)

          prompts.each_with_object({}) do |p, result|
            next unless p.is_a?(Hash)

            id = p["identifier"]
            next if id.nil?

            result[id.to_s] = p
          end
        end

        def build_prompt_entries_from_st(hash)
          prompts = hash["prompts"]
          prompts = [] unless prompts.is_a?(Array)
          prompt_order = extract_prompt_order_entries(hash["prompt_order"])

          prompts_by_id = prompts.each_with_object({}) do |p, result|
            next unless p.is_a?(Hash)

            id = p["identifier"]
            next if id.nil?

            result[id.to_s] = p
          end

          entries = []

          if prompt_order.is_a?(Array) && prompt_order.any?
            prompt_order.each do |order_entry|
              next unless order_entry.is_a?(Hash)

              id = order_entry["identifier"]
              next if id.nil?

              prompt_data = prompts_by_id[id.to_s] || {}
              enabled = order_entry.key?("enabled") ? Coerce.bool(order_entry["enabled"], default: true) : true

              entries << build_st_prompt_entry(id.to_s, prompt_data, enabled: enabled)
            end
          else
            prompts.each do |p|
              next unless p.is_a?(Hash)

              id = p["identifier"]
              next if id.nil?

              entries << build_st_prompt_entry(id.to_s, p)
            end
          end

          entries.empty? ? nil : entries
        end

        def extract_prompt_order_entries(raw)
          return nil unless raw.is_a?(Array) && raw.any?

          first = raw.first
          return raw unless first.is_a?(Hash)

          if first.key?("order")
            global_bucket = raw.find { |bucket| bucket["character_id"] == 100_000 }
            bucket = global_bucket || first
            Array(bucket["order"])
          else
            raw
          end
        end

        def build_st_prompt_entry(id, prompt_data, enabled: nil)
          normalized_id = ST_PINNED_IDS[id] || id

          marker = Coerce.bool(prompt_data["marker"], default: false)
          pinned = ST_PINNED_IDS.key?(id) || marker

          role = Coerce.role(prompt_data["role"], default: :system)
          position = prompt_data["injection_position"] == 1 ? :in_chat : :relative
          depth = (prompt_data["injection_depth"] || 4).to_i
          order = (prompt_data["injection_order"] || 100).to_i

          content = prompt_data["content"]
          content = content.nil? ? nil : content.to_s

          triggers = Coerce.triggers(prompt_data["injection_trigger"] || [])
          forbid_overrides = Coerce.bool(prompt_data["forbid_overrides"], default: false)

          enabled = Coerce.bool(prompt_data["enabled"], default: true) if enabled.nil? && prompt_data.key?("enabled")
          enabled = true if enabled.nil?

          Prompt::PromptEntry.new(
            id: normalized_id,
            name: prompt_data["name"] || normalized_id,
            enabled: enabled,
            pinned: pinned,
            role: role,
            position: position,
            depth: depth,
            order: order,
            content: content,
            triggers: triggers,
            forbid_overrides: forbid_overrides,
          )
        end

        def coerce_st_continue_postfix(value)
          return nil if value.nil?

          # Match ST's continue_postfix_types: 0=>"", 1=>" ", 2=>"\\n", 3=>"\\n\\n"
          if value.is_a?(Integer)
            return "" if value == 0
            return " " if value == 1
            return "\n" if value == 2
            return "\n\n" if value == 3
          end

          if value.is_a?(String) && value.strip.match?(/\A\d+\z/)
            return coerce_st_continue_postfix(value.strip.to_i)
          end

          value.to_s
        end

        def extract_instruct_settings(hash)
          instruct = hash["instruct"]
          return nil unless instruct.is_a?(Hash)

          Instruct.from_st_json(instruct)
        end

        def extract_context_settings(hash)
          context = hash["context"]
          return nil unless context.is_a?(Hash)

          ContextTemplate.from_st_json(context)
        end
      end
    end
  end
end
