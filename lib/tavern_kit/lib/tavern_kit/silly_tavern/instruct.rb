# frozen_string_literal: true

module TavernKit
  module SillyTavern
    # Instruct mode settings for text completion formatting.
    #
    # Based on SillyTavern's `instruct-mode.js`.
    Instruct = Data.define(
      :enabled,
      :preset,
      :input_sequence,
      :input_suffix,
      :output_sequence,
      :output_suffix,
      :system_sequence,
      :system_suffix,
      :last_system_sequence,
      :first_input_sequence,
      :first_output_sequence,
      :last_input_sequence,
      :last_output_sequence,
      :story_string_prefix,
      :story_string_suffix,
      :stop_sequence,
      :wrap,
      :macro,
      :names_behavior,
      :activation_regex,
      :bind_to_context,
      :user_alignment_message,
      :system_same_as_user,
      :sequences_as_stop_strings,
      :skip_examples,
    ) do
      def initialize(
        enabled: false,
        preset: "Alpaca",
        input_sequence: "### Instruction:",
        input_suffix: "",
        output_sequence: "### Response:",
        output_suffix: "",
        system_sequence: "",
        system_suffix: "",
        last_system_sequence: "",
        first_input_sequence: "",
        first_output_sequence: "",
        last_input_sequence: "",
        last_output_sequence: "",
        story_string_prefix: "",
        story_string_suffix: "",
        stop_sequence: "",
        wrap: true,
        macro: true,
        names_behavior: TavernKit::SillyTavern::Instruct::NamesBehavior::FORCE,
        activation_regex: "",
        bind_to_context: false,
        user_alignment_message: "",
        system_same_as_user: false,
        sequences_as_stop_strings: true,
        skip_examples: false
      )
        super(
          enabled: enabled == true,
          preset: preset.to_s,
          input_sequence: input_sequence.to_s,
          input_suffix: input_suffix.to_s,
          output_sequence: output_sequence.to_s,
          output_suffix: output_suffix.to_s,
          system_sequence: system_sequence.to_s,
          system_suffix: system_suffix.to_s,
          last_system_sequence: last_system_sequence.to_s,
          first_input_sequence: first_input_sequence.to_s,
          first_output_sequence: first_output_sequence.to_s,
          last_input_sequence: last_input_sequence.to_s,
          last_output_sequence: last_output_sequence.to_s,
          story_string_prefix: story_string_prefix.to_s,
          story_string_suffix: story_string_suffix.to_s,
          stop_sequence: stop_sequence.to_s,
          wrap: wrap != false,
          macro: macro != false,
          names_behavior: TavernKit::SillyTavern::Instruct::NamesBehavior.coerce(names_behavior),
          activation_regex: activation_regex.to_s,
          bind_to_context: bind_to_context == true,
          user_alignment_message: user_alignment_message.to_s,
          system_same_as_user: system_same_as_user == true,
          sequences_as_stop_strings: sequences_as_stop_strings != false,
          skip_examples: skip_examples == true,
        )
      end

      def enabled? = enabled == true
      def wrap? = wrap == true
      def macro? = macro == true
      def bind_to_context? = bind_to_context == true
      def system_same_as_user? = system_same_as_user == true
      def sequences_as_stop_strings? = sequences_as_stop_strings == true
      def skip_examples? = skip_examples == true

      def with(**overrides)
        self.class.new(**deconstruct_keys(nil).merge(overrides))
      end

      # Converts instruct mode sequences to an array of stopping strings.
      #
      # Follows ST's `getInstructStoppingSequences` behavior:
      # - Always includes stop_sequence when enabled
      # - When sequences_as_stop_strings is enabled, includes input/output/system sequences too
      # - Splits on "\n" so multi-line sequences become multiple stop strings
      # - Optionally prefixes "\n" when wrap is enabled
      # - Optional macro expansion when macro is enabled
      def stopping_sequences(user_name:, char_name:, macro_expander: nil)
        return [] unless enabled?

        input_seq = input_sequence.gsub(/\{\{name\}\}/i, user_name.to_s)
        output_seq = output_sequence.gsub(/\{\{name\}\}/i, char_name.to_s)
        first_output_seq = first_output_sequence.gsub(/\{\{name\}\}/i, char_name.to_s)
        last_output_seq = last_output_sequence.gsub(/\{\{name\}\}/i, char_name.to_s)
        system_seq = system_sequence.gsub(/\{\{name\}\}/i, "System")
        last_system_seq = last_system_sequence.gsub(/\{\{name\}\}/i, "System")

        combined = [stop_sequence]
        if sequences_as_stop_strings?
          combined.push(
            input_seq,
            output_seq,
            first_output_seq,
            last_output_seq,
            system_seq,
            last_system_seq,
          )
        end

        result = []
        combined.join("\n").split("\n").uniq.each do |sequence|
          next if sequence.nil?

          seq = sequence.to_s
          next if seq.empty?
          next if seq.strip.empty?

          seq = "\n#{seq}" if wrap?
          seq = macro_expander.call(seq) if macro? && macro_expander

          result << seq unless result.include?(seq)
        end

        result
      end

      def to_h
        {
          "enabled" => enabled,
          "preset" => preset,
          "input_sequence" => input_sequence,
          "input_suffix" => input_suffix,
          "output_sequence" => output_sequence,
          "output_suffix" => output_suffix,
          "system_sequence" => system_sequence,
          "system_suffix" => system_suffix,
          "last_system_sequence" => last_system_sequence,
          "first_input_sequence" => first_input_sequence,
          "first_output_sequence" => first_output_sequence,
          "last_input_sequence" => last_input_sequence,
          "last_output_sequence" => last_output_sequence,
          "story_string_prefix" => story_string_prefix,
          "story_string_suffix" => story_string_suffix,
          "stop_sequence" => stop_sequence,
          "wrap" => wrap,
          "macro" => macro,
          "names_behavior" => names_behavior,
          "activation_regex" => activation_regex,
          "bind_to_context" => bind_to_context,
          "user_alignment_message" => user_alignment_message,
          "system_same_as_user" => system_same_as_user,
          "sequences_as_stop_strings" => sequences_as_stop_strings,
          "skip_examples" => skip_examples,
        }
      end

      def self.from_st_json(hash)
        return new if hash.nil? || !hash.is_a?(Hash)

        h = hash.transform_keys(&:to_s)

        # Migration: separator_sequence => output_suffix
        if h.key?("separator_sequence") && !h.key?("output_suffix")
          h["output_suffix"] = h["separator_sequence"]
        end

        # Migration: names/names_force_groups => names_behavior
        if h.key?("names")
          h["names_behavior"] =
            if h["names"] == true
              TavernKit::SillyTavern::Instruct::NamesBehavior::ALWAYS
            elsif h["names_force_groups"] == true
              TavernKit::SillyTavern::Instruct::NamesBehavior::FORCE
            else
              TavernKit::SillyTavern::Instruct::NamesBehavior::NONE
            end
        end

        new(
          enabled: h["enabled"],
          preset: h["preset"] || h["name"] || "Alpaca",
          input_sequence: h["input_sequence"],
          input_suffix: h["input_suffix"],
          output_sequence: h["output_sequence"],
          output_suffix: h["output_suffix"],
          system_sequence: h["system_sequence"],
          system_suffix: h["system_suffix"],
          last_system_sequence: h["last_system_sequence"],
          first_input_sequence: h["first_input_sequence"],
          first_output_sequence: h["first_output_sequence"],
          last_input_sequence: h["last_input_sequence"],
          last_output_sequence: h["last_output_sequence"],
          story_string_prefix: h["story_string_prefix"],
          story_string_suffix: h["story_string_suffix"],
          stop_sequence: h["stop_sequence"] || h["instructStop"],
          wrap: h.key?("wrap") ? h["wrap"] : true,
          macro: h.key?("macro") ? h["macro"] : true,
          names_behavior: h["names_behavior"],
          activation_regex: h["activation_regex"],
          bind_to_context: h["bind_to_context"],
          user_alignment_message: h["user_alignment_message"],
          system_same_as_user: h["system_same_as_user"],
          sequences_as_stop_strings: h.key?("sequences_as_stop_strings") ? h["sequences_as_stop_strings"] : true,
          skip_examples: h["skip_examples"],
        )
      end
    end

    module Instruct::NamesBehavior
      NONE = :none
      FORCE = :force
      ALWAYS = :always

      ALL = [NONE, FORCE, ALWAYS].freeze

      def self.coerce(value)
        return FORCE if value.nil?

        case value
        when 0, "0" then return NONE
        when 1, "1" then return FORCE
        when 2, "2" then return ALWAYS
        end

        sym = value.to_s.strip.downcase.to_sym
        ALL.include?(sym) ? sym : FORCE
      end
    end
  end
end
