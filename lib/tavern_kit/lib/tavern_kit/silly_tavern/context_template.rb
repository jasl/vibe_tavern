# frozen_string_literal: true

module TavernKit
  module SillyTavern
    # Context template settings for Story String assembly.
    #
    # Story String is a Handlebars-like template that conditionally assembles
    # character context (system/description/personality/scenario/persona/etc).
    #
    # Note: this renderer only handles Handlebars blocks and known placeholders.
    # Unknown `{{macro}}` tokens are preserved for the Macro engine.
    ContextTemplate = Data.define(
      :preset,
      :story_string,
      :chat_start,
      :example_separator,
      :use_stop_strings,
      :names_as_stop_strings,
      :story_string_position,
      :story_string_role,
      :story_string_depth,
    ) do
      def initialize(
        preset: "Default",
        story_string: TavernKit::SillyTavern::ContextTemplate::DEFAULT_STORY_STRING,
        chat_start: TavernKit::SillyTavern::ContextTemplate::DEFAULT_CHAT_START,
        example_separator: TavernKit::SillyTavern::ContextTemplate::DEFAULT_EXAMPLE_SEPARATOR,
        use_stop_strings: true,
        names_as_stop_strings: true,
        story_string_position: TavernKit::SillyTavern::ContextTemplate::Position::IN_PROMPT,
        story_string_role: TavernKit::SillyTavern::ContextTemplate::Role::SYSTEM,
        story_string_depth: 1
      )
        if !preset.nil? && !preset.is_a?(String)
          raise ArgumentError, "preset must be a String, got: #{preset.class}"
        end

        super(
          preset: preset.to_s,
          story_string: story_string.to_s,
          chat_start: chat_start.to_s,
          example_separator: example_separator.to_s,
          use_stop_strings: use_stop_strings == true,
          names_as_stop_strings: names_as_stop_strings == true,
          story_string_position: TavernKit::SillyTavern::ContextTemplate::Position.coerce(story_string_position),
          story_string_role: TavernKit::SillyTavern::ContextTemplate::Role.coerce(story_string_role),
          story_string_depth: [story_string_depth.to_i, 0].max,
        )
      end

      def use_stop_strings? = use_stop_strings == true
      def names_as_stop_strings? = names_as_stop_strings == true

      def with(**overrides)
        self.class.new(**deconstruct_keys(nil).merge(overrides))
      end

      # Render the story string template with the provided params.
      #
      # - `{{field}}` → value or kept as-is if field is unknown
      # - `{{#if field}}...{{/if}}` → conditional block
      # - `{{#unless field}}...{{/unless}}` → negative conditional
      #
      # @param params [Hash] template parameters
      # @return [String]
      def render(params = {})
        p = params.is_a?(Hash) ? params.transform_keys(&:to_s) : {}

        result = story_string.to_s.dup
        result = process_conditionals(result, p)
        result = process_unless_blocks(result, p)
        result = replace_fields(result, p)

        # ST removes leading newlines after Handlebars rendering.
        result = result.sub(/^\n+/, "")

        result = result.rstrip
        return "" if result.empty?

        # When story_string is injected as an in-chat prompt, ST avoids forcing
        # a trailing newline (message sequences wrap it).
        story_string_position == self.class::Position::IN_CHAT ? result : "#{result}\n"
      end

      def to_h
        {
          "preset" => preset,
          "story_string" => story_string,
          "chat_start" => chat_start,
          "example_separator" => example_separator,
          "use_stop_strings" => use_stop_strings,
          "names_as_stop_strings" => names_as_stop_strings,
          "story_string_position" => story_string_position,
          "story_string_role" => story_string_role,
          "story_string_depth" => story_string_depth,
        }
      end

      def self.from_st_json(hash)
        return new if hash.nil? || !hash.is_a?(Hash)

        h = hash.transform_keys(&:to_s)
        new(
          preset: h["preset"] || h["name"] || "Default",
          story_string: h["story_string"],
          chat_start: h["chat_start"],
          example_separator: h["example_separator"],
          use_stop_strings: h.key?("use_stop_strings") ? h["use_stop_strings"] : true,
          names_as_stop_strings: h.key?("names_as_stop_strings") ? h["names_as_stop_strings"] : true,
          story_string_position: h["story_string_position"],
          story_string_role: h["story_string_role"],
          story_string_depth: h["story_string_depth"],
        )
      end

      private

      def process_conditionals(template, params)
        template.gsub(/\{\{#if\s+(\w+)\}\}(.*?)\{\{\/if\}\}/m) do
          field = Regexp.last_match(1)
          content = Regexp.last_match(2)

          truthy?(params[field]) ? process_conditionals(content, params) : ""
        end
      end

      def process_unless_blocks(template, params)
        template.gsub(/\{\{#unless\s+(\w+)\}\}(.*?)\{\{\/unless\}\}/m) do
          field = Regexp.last_match(1)
          content = Regexp.last_match(2)

          truthy?(params[field]) ? "" : process_unless_blocks(content, params)
        end
      end

      def replace_fields(template, params)
        template.gsub(/\{\{(\w+)\}\}/) do |match|
          field = Regexp.last_match(1)

          # Preserve unknown macros for the Macro engine.
          next match unless self.class::FIELD_KEYS.include?(field)

          value = params[field]
          case field
          when "loreBefore" then params["wiBefore"].to_s
          when "loreAfter" then params["wiAfter"].to_s
          else value.to_s
          end
        end
      end

      def truthy?(value)
        return false if value.nil?
        return false if value == false
        return false if value.is_a?(String) && value.strip.empty?

        true
      end
    end

    module ContextTemplate::Position
      IN_PROMPT = :in_prompt
      IN_CHAT = :in_chat
      BEFORE_PROMPT = :before_prompt

      ALL = [IN_PROMPT, IN_CHAT, BEFORE_PROMPT].freeze

      def self.coerce(value)
        return IN_PROMPT if value.nil?

        case value
        when 0, "0" then return IN_PROMPT
        when 1, "1" then return IN_CHAT
        when 2, "2" then return BEFORE_PROMPT
        end

        sym = value.to_s.strip.downcase.gsub("-", "_").to_sym
        ALL.include?(sym) ? sym : IN_PROMPT
      end
    end

    module ContextTemplate::Role
      SYSTEM = :system
      USER = :user
      ASSISTANT = :assistant

      ALL = [SYSTEM, USER, ASSISTANT].freeze

      def self.coerce(value)
        return SYSTEM if value.nil?

        case value
        when 0, "0" then return SYSTEM
        when 1, "1" then return USER
        when 2, "2" then return ASSISTANT
        end

        sym = value.to_s.strip.downcase.to_sym
        ALL.include?(sym) ? sym : SYSTEM
      end
    end

    ContextTemplate::DEFAULT_STORY_STRING = <<~TEMPLATE.chomp
      {{#if system}}{{system}}
      {{/if}}{{#if description}}{{description}}
      {{/if}}{{#if personality}}{{char}}'s personality: {{personality}}
      {{/if}}{{#if scenario}}Scenario: {{scenario}}
      {{/if}}{{#if persona}}{{persona}}
      {{/if}}
    TEMPLATE

    ContextTemplate::DEFAULT_CHAT_START = "***"
    ContextTemplate::DEFAULT_EXAMPLE_SEPARATOR = "***"

    ContextTemplate::FIELD_KEYS = %w[
      system
      description
      personality
      scenario
      persona
      char
      user
      wiBefore
      wiAfter
      loreBefore
      loreAfter
      anchorBefore
      anchorAfter
      mesExamples
      mesExamplesRaw
    ].freeze
  end
end
