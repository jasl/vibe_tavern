# frozen_string_literal: true

module TavernKit
  module SillyTavern
    # SillyTavern preset configuration (Prompt Manager + generation settings).
    #
    # This object is intentionally ST-shaped and lives in the ST layer. Core
    # only relies on the minimal budgeting interface (`context_window_tokens`,
    # `reserved_response_tokens`).
    Preset = Data.define(
      # === Prompt templates ===
      :main_prompt,
      :post_history_instructions,
      :enhance_definitions,
      :auxiliary_prompt,
      :send_if_empty,
      :new_chat_prompt,
      :new_group_chat_prompt,
      :new_example_chat_prompt,
      :continue_nudge_prompt,
      :group_nudge_prompt,
      :impersonation_prompt,
      :assistant_prefill,
      :assistant_impersonation,

      # === Prompt manager ===
      :use_sysprompt,
      :squash_system_messages,
      :names_behavior,
      :custom_prompt_post_processing,
      :bias_preset_selected,
      :prompt_entries,
      :pinned_group_resolver,

      # === Budgeting ===
      :context_window_tokens,
      :reserved_response_tokens,
      :message_token_overhead,
      :max_context_unlocked,

      # === World Info defaults ===
      :world_info_depth,
      :world_info_budget,
      :world_info_budget_cap,
      :world_info_include_names,
      :world_info_min_activations,
      :world_info_min_activations_depth_max,
      :world_info_use_group_scoring,

      # === Author's Note defaults ===
      :authors_note,
      :authors_note_frequency,
      :authors_note_position,
      :authors_note_depth,
      :authors_note_role,
      :authors_note_allow_wi_scan,

      # === Format templates ===
      :wi_format,
      :scenario_format,
      :personality_format,

      # === Sampling ===
      :temperature,
      :top_p,
      :top_k,
      :top_a,
      :min_p,
      :frequency_penalty,
      :presence_penalty,
      :repetition_penalty,

      # === Misc behaviors ===
      :continue_prefill,
      :continue_postfix,
      :examples_behavior,
      :prefer_char_prompt,
      :prefer_char_instructions,
      :character_lore_insertion_strategy,

      # === Stop strings ===
      :custom_stopping_strings,
      :custom_stopping_strings_macro,
      :single_line,

      # === Instruct / Context ===
      :instruct,
      :context_template,
    ) do
      def initialize(
        main_prompt: TavernKit::SillyTavern::Preset::DEFAULT_MAIN_PROMPT,
        post_history_instructions: "",
        enhance_definitions: TavernKit::SillyTavern::Preset::DEFAULT_ENHANCE_DEFINITIONS,
        auxiliary_prompt: "",
        send_if_empty: "",
        new_chat_prompt: TavernKit::SillyTavern::Preset::DEFAULT_NEW_CHAT_PROMPT,
        new_group_chat_prompt: TavernKit::SillyTavern::Preset::DEFAULT_NEW_GROUP_CHAT_PROMPT,
        new_example_chat_prompt: TavernKit::SillyTavern::Preset::DEFAULT_NEW_EXAMPLE_CHAT_PROMPT,
        continue_nudge_prompt: TavernKit::SillyTavern::Preset::DEFAULT_CONTINUE_NUDGE_PROMPT,
        group_nudge_prompt: TavernKit::SillyTavern::Preset::DEFAULT_GROUP_NUDGE_PROMPT,
        impersonation_prompt: TavernKit::SillyTavern::Preset::DEFAULT_IMPERSONATION_PROMPT,
        assistant_prefill: "",
        assistant_impersonation: "",

        use_sysprompt: false,
        squash_system_messages: false,
        names_behavior: TavernKit::SillyTavern::Preset::NamesBehavior::DEFAULT,
        custom_prompt_post_processing: nil,
        bias_preset_selected: nil,
        prompt_entries: nil,
        pinned_group_resolver: nil,

        context_window_tokens: 4096,
        reserved_response_tokens: 300,
        message_token_overhead: 4,
        max_context_unlocked: false,

        world_info_depth: nil,
        world_info_budget: nil,
        world_info_budget_cap: 0,
        world_info_include_names: true,
        world_info_min_activations: 0,
        world_info_min_activations_depth_max: 0,
        world_info_use_group_scoring: false,

        authors_note: "",
        authors_note_frequency: 1,
        authors_note_position: TavernKit::SillyTavern::Preset::DEFAULT_AUTHORS_NOTE_POSITION,
        authors_note_depth: TavernKit::SillyTavern::Preset::DEFAULT_AUTHORS_NOTE_DEPTH,
        authors_note_role: TavernKit::SillyTavern::Preset::DEFAULT_AUTHORS_NOTE_ROLE,
        authors_note_allow_wi_scan: false,

        wi_format: TavernKit::SillyTavern::Preset::DEFAULT_WI_FORMAT,
        scenario_format: TavernKit::SillyTavern::Preset::DEFAULT_SCENARIO_FORMAT,
        personality_format: TavernKit::SillyTavern::Preset::DEFAULT_PERSONALITY_FORMAT,

        temperature: 1.0,
        top_p: 1.0,
        top_k: 0,
        top_a: 0.0,
        min_p: 0.0,
        frequency_penalty: 0.0,
        presence_penalty: 0.0,
        repetition_penalty: 1.0,

        continue_prefill: false,
        continue_postfix: " ",
        examples_behavior: :gradually_push_out,
        prefer_char_prompt: true,
        prefer_char_instructions: true,
        character_lore_insertion_strategy: :character_lore_first,

        custom_stopping_strings: "",
        custom_stopping_strings_macro: true,
        single_line: false,

        instruct: nil,
        context_template: nil
      )
        prompt_entries = if prompt_entries.nil?
          nil
        else
          Array(prompt_entries).filter_map do |entry|
            entry.is_a?(Prompt::PromptEntry) ? entry : Prompt::PromptEntry.from_hash(entry)
          end.freeze
        end

        super(
          main_prompt: main_prompt.to_s,
          post_history_instructions: post_history_instructions.to_s,
          enhance_definitions: enhance_definitions.to_s,
          auxiliary_prompt: auxiliary_prompt.to_s,
          send_if_empty: send_if_empty.to_s,
          new_chat_prompt: new_chat_prompt.to_s,
          new_group_chat_prompt: new_group_chat_prompt.to_s,
          new_example_chat_prompt: new_example_chat_prompt.to_s,
          continue_nudge_prompt: continue_nudge_prompt.to_s,
          group_nudge_prompt: group_nudge_prompt.to_s,
          impersonation_prompt: impersonation_prompt.to_s,
          assistant_prefill: assistant_prefill.to_s,
          assistant_impersonation: assistant_impersonation.to_s,

          use_sysprompt: use_sysprompt == true,
          squash_system_messages: squash_system_messages == true,
          names_behavior: TavernKit::SillyTavern::Preset::NamesBehavior.coerce(names_behavior),
          custom_prompt_post_processing: custom_prompt_post_processing&.to_s,
          bias_preset_selected: bias_preset_selected&.to_s,
          prompt_entries: prompt_entries,
          pinned_group_resolver: pinned_group_resolver,

          context_window_tokens: context_window_tokens.to_i,
          reserved_response_tokens: [reserved_response_tokens.to_i, 0].max,
          message_token_overhead: [message_token_overhead.to_i, 0].max,
          max_context_unlocked: max_context_unlocked == true,

          world_info_depth: world_info_depth.nil? ? nil : [world_info_depth.to_i, 0].max,
          world_info_budget: world_info_budget.nil? ? nil : [world_info_budget.to_i, 0].max,
          world_info_budget_cap: [world_info_budget_cap.to_i, 0].max,
          world_info_include_names: world_info_include_names != false,
          world_info_min_activations: [world_info_min_activations.to_i, 0].max,
          world_info_min_activations_depth_max: [world_info_min_activations_depth_max.to_i, 0].max,
          world_info_use_group_scoring: world_info_use_group_scoring == true,

          authors_note: authors_note.to_s,
          authors_note_frequency: [authors_note_frequency.to_i, 0].max,
          authors_note_position: Coerce.authors_note_position(
            authors_note_position,
            default: TavernKit::SillyTavern::Preset::DEFAULT_AUTHORS_NOTE_POSITION,
          ),
          authors_note_depth: [authors_note_depth.to_i, 0].max,
          authors_note_role: Coerce.role(authors_note_role, default: TavernKit::SillyTavern::Preset::DEFAULT_AUTHORS_NOTE_ROLE),
          authors_note_allow_wi_scan: authors_note_allow_wi_scan == true,

          wi_format: wi_format.to_s,
          scenario_format: scenario_format.to_s,
          personality_format: personality_format.to_s,

          temperature: temperature.to_f,
          top_p: top_p.to_f,
          top_k: top_k.to_i,
          top_a: top_a.to_f,
          min_p: min_p.to_f,
          frequency_penalty: frequency_penalty.to_f,
          presence_penalty: presence_penalty.to_f,
          repetition_penalty: repetition_penalty.to_f,

          continue_prefill: continue_prefill == true,
          continue_postfix: continue_postfix.to_s,
          examples_behavior: Coerce.examples_behavior(examples_behavior, default: :gradually_push_out),
          prefer_char_prompt: prefer_char_prompt != false,
          prefer_char_instructions: prefer_char_instructions != false,
          character_lore_insertion_strategy: Coerce.insertion_strategy(character_lore_insertion_strategy, default: :character_lore_first),

          custom_stopping_strings: custom_stopping_strings.to_s,
          custom_stopping_strings_macro: custom_stopping_strings_macro != false,
          single_line: single_line == true,

          instruct: coerce_instruct(instruct),
          context_template: coerce_context_template(context_template),
        )
      end

      def max_prompt_tokens
        context_window_tokens.to_i - reserved_response_tokens.to_i
      end

      def effective_instruct
        instruct || Instruct.new
      end

      def effective_context_template
        context_template || ContextTemplate.new
      end

      def effective_prompt_entries
        prompt_entries || self.class.default_prompt_entries
      end

      def with(**overrides)
        self.class.new(**deconstruct_keys(nil).merge(overrides))
      end

      # Assemble stopping strings following SillyTavern's 4-source merge:
      # 1) names-based stops (if context.names_as_stop_strings)
      # 2) instruct stop sequences
      # 3) context markers (chat_start + example_separator, if context.use_stop_strings)
      # 4) custom stops + ephemeral stops
      #
      # @param context [Prompt::Context]
      # @param macro_expander [#call, nil] optional macro expander (Wave 3+)
      # @return [Array<String>]
      def stopping_strings(context, macro_expander: nil)
        ctx = context

        user_name = ctx&.user&.name&.to_s
        user_name = "User" if user_name.nil? || user_name.strip.empty?

        char_name = ctx&.character&.name&.to_s
        char_name = "Assistant" if char_name.nil? || char_name.strip.empty?

        generation_type = ctx&.generation_type&.to_sym || :normal
        is_impersonate = generation_type == :impersonate
        is_continue = generation_type == :continue

        group_names = extract_group_member_names(ctx&.group, exclude: char_name)

        result = []

        # 1) Names-based stops
        if effective_context_template.names_as_stop_strings?
          char_string = "\n#{char_name}:"
          user_string = "\n#{user_name}:"

          result << (is_impersonate ? char_string : user_string)
          result << user_string

          if is_continue && last_message_from_user?(ctx&.history)
            result << char_string
          end

          group_names.each do |name|
            result << "\n#{name}:"
          end
        end

        # 2) Instruct sequences
        result.concat(
          effective_instruct.stopping_sequences(
            user_name: user_name,
            char_name: char_name,
            macro_expander: macro_expander,
          ),
        )

        # 3) Context markers
        if effective_context_template.use_stop_strings?
          chat_start = effective_context_template.chat_start.to_s
          example_sep = effective_context_template.example_separator.to_s

          if !chat_start.strip.empty?
            expanded = macro_expander ? macro_expander.call(chat_start) : chat_start
            result << "\n#{expanded}"
          end

          if !example_sep.strip.empty?
            expanded = macro_expander ? macro_expander.call(example_sep) : example_sep
            result << "\n#{expanded}"
          end
        end

        # 4) Custom + ephemeral stopping strings
        result.concat(custom_stops(macro_expander: macro_expander))
        result.concat(Array(ctx&.[](:ephemeral_stopping_strings)))

        result.unshift("\n") if single_line == true

        result
          .map(&:to_s)
          .reject { |s| s.empty? }
          .uniq
      end

      def self.from_st_preset_json(hash)
        Preset::StImporter.new(hash).to_preset
      end

      def self.load_st_preset_file(path)
        Preset::StImporter.load_file(path)
      end

      def self.default_prompt_entries
        @default_prompt_entries ||= [
          Prompt::PromptEntry.new(id: "main_prompt", pinned: true, role: :system),
          Prompt::PromptEntry.new(id: "world_info_before_char_defs", pinned: true, role: :system),
          Prompt::PromptEntry.new(id: "persona_description", pinned: true, role: :system),
          Prompt::PromptEntry.new(id: "character_description", pinned: true, role: :system),
          Prompt::PromptEntry.new(id: "character_personality", pinned: true, role: :system),
          Prompt::PromptEntry.new(id: "scenario", pinned: true, role: :system),
          Prompt::PromptEntry.new(id: "enhance_definitions", pinned: true, role: :system, enabled: false),
          Prompt::PromptEntry.new(id: "auxiliary_prompt", pinned: true, role: :system),
          Prompt::PromptEntry.new(id: "world_info_after_char_defs", pinned: true, role: :system),
          Prompt::PromptEntry.new(id: "world_info_before_example_messages", pinned: true, role: :system),
          Prompt::PromptEntry.new(id: "chat_examples", pinned: true, role: :system),
          Prompt::PromptEntry.new(id: "world_info_after_example_messages", pinned: true, role: :system),
          Prompt::PromptEntry.new(
            id: "authors_note",
            pinned: true,
            role: TavernKit::SillyTavern::Preset::DEFAULT_AUTHORS_NOTE_ROLE,
            position: TavernKit::SillyTavern::Preset::DEFAULT_AUTHORS_NOTE_POSITION,
            depth: TavernKit::SillyTavern::Preset::DEFAULT_AUTHORS_NOTE_DEPTH,
          ),
          Prompt::PromptEntry.new(id: "chat_history", pinned: true, role: :system),
          Prompt::PromptEntry.new(id: "post_history_instructions", pinned: true, role: :system),
        ]
      end

      private

      def coerce_instruct(value)
        return nil if value.nil?
        return value if value.is_a?(Instruct)
        return Instruct.from_st_json(value) if value.is_a?(Hash)

        nil
      end

      def coerce_context_template(value)
        return nil if value.nil?
        return value if value.is_a?(ContextTemplate)
        return ContextTemplate.from_st_json(value) if value.is_a?(Hash)

        nil
      end

      def custom_stops(macro_expander:)
        return [] if custom_stopping_strings.to_s.strip.empty?

        parsed =
          begin
            JSON.parse(custom_stopping_strings.to_s)
          rescue JSON::ParserError
            []
          end

        strings = Array(parsed).select { |s| s.is_a?(String) && !s.empty? }

        if custom_stopping_strings_macro == true && macro_expander
          strings = strings.map { |s| macro_expander.call(s) }
        end

        strings
      end

      def extract_group_member_names(group, exclude:)
        members =
          if group.respond_to?(:members)
            group.members
          elsif group.is_a?(Array)
            group
          else
            nil
          end

        Array(members).filter_map do |member|
          name =
            if member.respond_to?(:name)
              member.name
            else
              member
            end

          n = name.to_s.strip
          next nil if n.empty?
          next nil if exclude && n == exclude

          n
        end
      end

      def last_message_from_user?(history)
        return false if history.nil?

        h =
          begin
            ChatHistory.wrap(history)
          rescue ArgumentError
            nil
          end
        return false unless h

        msg = h.last(1).first
        return false unless msg

        msg.respond_to?(:role) && msg.role.to_sym == :user
      end
    end

    Preset::DEFAULT_MAIN_PROMPT = "Write {{char}}'s next reply in a fictional chat between {{charIfNotGroup}} and {{user}}."
    Preset::DEFAULT_ENHANCE_DEFINITIONS = "If you have more knowledge of {{char}}, add to the character's lore and personality to enhance them but keep the Character Sheet's definitions absolute."
    Preset::DEFAULT_NEW_CHAT_PROMPT = "[Start a new Chat]"
    Preset::DEFAULT_NEW_GROUP_CHAT_PROMPT = "[Start a new group chat. Group members: {{group}}]"
    Preset::DEFAULT_NEW_EXAMPLE_CHAT_PROMPT = "[Example Chat]"
    Preset::DEFAULT_GROUP_NUDGE_PROMPT = "[Write the next reply only as {{char}}.]"
    Preset::DEFAULT_CONTINUE_NUDGE_PROMPT = "[Continue your last message without repeating its original content.]"
    Preset::DEFAULT_IMPERSONATION_PROMPT = "[Write your next reply from the point of view of {{user}}, using the chat history so far as a guideline for the writing style of {{user}}. Don't write as {{char}} or system. Don't describe actions of {{char}}.]"

    Preset::DEFAULT_WI_FORMAT = "{0}"
    Preset::DEFAULT_SCENARIO_FORMAT = "{{scenario}}"
    Preset::DEFAULT_PERSONALITY_FORMAT = "{{personality}}"

    Preset::DEFAULT_AUTHORS_NOTE_POSITION = :in_chat
    Preset::DEFAULT_AUTHORS_NOTE_DEPTH = 4
    Preset::DEFAULT_AUTHORS_NOTE_ROLE = :system

    module Preset::NamesBehavior
      NONE = :none
      DEFAULT = :default
      COMPLETION = :completion
      CONTENT = :content

      ALL = [NONE, DEFAULT, COMPLETION, CONTENT].freeze

      def self.coerce(value)
        return DEFAULT if value.nil?

        case value
        when -1, "-1" then return NONE
        when 0, "0" then return DEFAULT
        when 1, "1" then return COMPLETION
        when 2, "2" then return CONTENT
        end

        sym = value.to_s.strip.downcase.to_sym
        ALL.include?(sym) ? sym : DEFAULT
      end
    end
  end
end

require_relative "preset/st_importer"
