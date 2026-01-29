# frozen_string_literal: true

module TavernKit
  # Coercion helpers for converting loose inputs to internal values.
  # Follows Ruby's duck typing philosophy - trust the input, convert gracefully.
  module Coerce
    module_function

    TRUE_STRINGS = %w[1 true yes y on].freeze
    FALSE_STRINGS = %w[0 false no n off].freeze

    ROLE_MAP = { 0 => :system, 1 => :user, 2 => :assistant }.freeze
    AN_POSITION_MAP = { 0 => :in_prompt, 1 => :in_chat, 2 => :before_prompt }.freeze

    def bool(value, default:)
      return default if value.nil?
      return value if value == true || value == false

      v = value.to_s.strip.downcase
      TRUE_STRINGS.include?(v) || (FALSE_STRINGS.include?(v) ? false : default)
    end

    def generation_type(value, default: :normal)
      return default unless value
      return TRIGGER_CODE_MAP[value] || default if value.is_a?(Integer)

      raw = value.to_s.strip
      return default if raw.empty?
      return TRIGGER_CODE_MAP[raw.to_i] || default if raw.match?(/\A\d+\z/)

      sym = raw.downcase.to_sym
      GENERATION_TYPES.include?(sym) ? sym : default
    end

    def trigger_value(value)
      return TRIGGER_CODE_MAP[value] if value.is_a?(Integer) && TRIGGER_CODE_MAP.key?(value)

      raw = value.to_s.strip
      return TRIGGER_CODE_MAP[raw.to_i] if raw.match?(/\A\d+\z/) && TRIGGER_CODE_MAP.key?(raw.to_i)

      sym = raw.downcase.to_sym
      GENERATION_TYPES.include?(sym) ? sym : nil
    end

    def triggers(value)
      return [].freeze unless value

      Array(value).filter_map { |v| trigger_value(v) }.uniq.freeze
    end

    def role(value, default: :system)
      return default unless value
      return ROLE_MAP[value] || default if value.is_a?(Integer)

      v = value.to_s.strip.downcase
      return default if v.empty?

      case v
      when "system", "0" then :system
      when "user", "1" then :user
      when "assistant", "2" then :assistant
      when "tool" then :tool
      when "function" then :function
      else default
      end
    end

    def authors_note_position(value, default: :in_chat)
      return default unless value
      return AN_POSITION_MAP[value] || default if value.is_a?(Integer)

      v = value.to_s.strip.downcase
      return default if v.empty?

      case v
      when "in_chat", "chat", "inchart", "inchat" then :in_chat
      when "in_prompt", "prompt", "after", "after_scenario", "scenario" then :in_prompt
      when "before_prompt", "before", "before_scenario" then :before_prompt
      else default
      end
    end

    def insertion_strategy(value, default: :sorted_evenly)
      return default unless value

      v = value.to_s.strip.downcase
      return default if v.empty?

      case v
      when "sorted_evenly", "sorted", "evenly" then :sorted_evenly
      when "character_lore_first", "character", "first", "char_first" then :character_lore_first
      when "global_lore_first", "global", "global_first" then :global_lore_first
      else
        sym = v.to_sym
        INSERTION_STRATEGIES.include?(sym) ? sym : default
      end
    end

    INSERTION_STRATEGIES = %i[sorted_evenly character_lore_first global_lore_first].freeze

    def examples_behavior(value, default: :gradually_push_out)
      return default unless value

      v = value.to_s.strip.downcase
      return default if v.empty?

      case v
      when "gradually_push_out", "trim", "push_out" then :gradually_push_out
      when "always_keep", "keep", "always" then :always_keep
      when "disabled", "off", "none" then :disabled
      else default
      end
    end

    # Coerce a loose timestamp input (string/float/etc) into an Integer unix timestamp.
    #
    # Returns nil for blank/invalid inputs.
    def unix_timestamp(value)
      case value
      when nil
        nil
      when Integer
        value
      when Numeric
        value.to_i
      else
        s = value.to_s.strip
        return nil if s.empty?
        return Integer(s) if s.match?(/\A-?\d+\z/)

        nil
      end
    rescue ArgumentError, TypeError
      nil
    end
  end
end
