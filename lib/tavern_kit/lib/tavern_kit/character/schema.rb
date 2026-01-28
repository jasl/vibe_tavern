# frozen_string_literal: true

require "easy_talk"
require_relative "asset_schema"
require_relative "character_book_schema"
require_relative "extensions_schema"

module TavernKit
  class Character
    # Schema for Character Card data (V2/V3 unified).
    #
    # This schema represents the `data` object within a Character Card.
    # It supports all fields from both V2 and V3 specifications, with V3
    # being a superset of V2.
    #
    # @see https://github.com/malfoyslastname/character-card-spec-v2
    # @see https://github.com/kwaroran/character-card-spec-v3
    class Schema
      include EasyTalk::Schema

      define_schema do
        title "Character Card Data"
        description "Character Card data object (V2/V3 unified)"

        # ===== V2 Base Fields =====

        property :name, String, min_length: 1,
          description: "Character's display name"

        property :description, T.nilable(String), optional: true,
          description: "Character's description and backstory"

        property :personality, T.nilable(String), optional: true,
          description: "Character's personality traits"

        property :scenario, T.nilable(String), optional: true,
          description: "The roleplay scenario or setting"

        property :first_mes, T.nilable(String), optional: true,
          description: "First message/greeting from the character"

        property :mes_example, T.nilable(String), optional: true,
          description: "Example dialogue in <START> block format"

        property :creator_notes, T.nilable(String), optional: true,
          description: "Notes from the card creator for users"

        property :system_prompt, T.nilable(String), optional: true,
          description: "Custom system prompt override"

        property :post_history_instructions, T.nilable(String), optional: true,
          description: "Instructions inserted after chat history"

        property :alternate_greetings, T::Array[String], optional: true,
          description: "Alternative first messages"

        property :character_book, T.nilable(CharacterBookSchema), optional: true,
          description: "Embedded character-specific lorebook"

        property :tags, T::Array[String], optional: true,
          description: "Tags for categorization"

        property :creator, T.nilable(String), optional: true,
          description: "Card creator's name"

        property :character_version, T.nilable(String), optional: true,
          description: "Version string for the character"

        property :extensions, T.nilable(ExtensionsSchema), optional: true,
          description: "Application-specific extension data"

        # ===== V3 Additions =====

        property :group_only_greetings, T::Array[String],
          description: "Greetings used only in group chat contexts"

        property :assets, T.nilable(T::Array[AssetSchema]), optional: true,
          description: "Embedded or referenced assets"

        property :nickname, T.nilable(String), optional: true,
          description: "Character nickname (replaces name in {{char}} macro)"

        property :creator_notes_multilingual, T.nilable(ExtensionsSchema), optional: true,
          description: "Localized creator notes by ISO 639-1 language code"

        property :source, T.nilable(T::Array[String]), optional: true,
          description: "Source URLs or IDs for the character card"

        property :creation_date, T.nilable(Integer), optional: true,
          description: "Creation date as Unix timestamp (seconds)"

        property :modification_date, T.nilable(Integer), optional: true,
          description: "Last modification date as Unix timestamp (seconds)"
      end

      def display_name
        nickname_val = respond_to?(:nickname) ? nickname : nil
        (nickname_val && !nickname_val.to_s.strip.empty?) ? nickname_val : name
      end

      def nickname?
        nickname_val = respond_to?(:nickname) ? nickname : nil
        nickname_val && !nickname_val.to_s.strip.empty?
      end

      def character_book?
        cb = respond_to?(:character_book) ? character_book : nil
        cb && !cb.empty?
      end

      def assets?
        assets_val = respond_to?(:assets) ? assets : nil
        assets_val && assets_val.any?
      end

      def main_icon
        assets&.find(&:main_icon?)
      end

      def main_background
        assets&.find(&:main_background?)
      end

      def all_greetings
        greetings = []
        greetings << first_mes if first_mes && !first_mes.to_s.strip.empty?
        greetings.concat(alternate_greetings) if alternate_greetings&.any?
        greetings
      end

      def group_greetings
        all_greetings + (group_only_greetings || [])
      end

      def creator_notes_for(lang = "en")
        return creator_notes unless creator_notes_multilingual && !creator_notes_multilingual.empty?

        creator_notes_multilingual[lang] ||
          creator_notes_multilingual["en"] ||
          creator_notes
      end

      def v3_features?
        (respond_to?(:assets) && assets) ||
          (respond_to?(:nickname) && nickname && !nickname.to_s.strip.empty?) ||
          (respond_to?(:creator_notes_multilingual) && creator_notes_multilingual) ||
          (respond_to?(:source) && source) ||
          (respond_to?(:creation_date) && creation_date) ||
          (respond_to?(:modification_date) && modification_date)
      end

      # =====================
      # SillyTavern Extensions
      # =====================

      def talkativeness?
        extension_key?(:talkativeness)
      end

      def talkativeness_factor(default: 0.5)
        return default unless talkativeness?

        raw = extension_value(:talkativeness)
        number = coerce_js_number(raw)
        number.nan? ? default : number
      end

      def world_name
        raw = extension_value(:world)
        name = raw.to_s.strip
        name.empty? ? nil : name
      end

      def extra_world_names
        raw = extension_value(:extra_worlds)
        return [] unless raw.is_a?(Array)

        raw.map { |w| w.to_s.strip }.reject(&:empty?)
      end

      private

      def extension_key?(key)
        ext = respond_to?(:extensions) ? extensions : nil
        return false unless ext.is_a?(Hash)

        ext.key?(key.to_s) || ext.key?(key.to_sym)
      end

      def extension_value(key)
        ext = respond_to?(:extensions) ? extensions : nil
        return nil unless ext.is_a?(Hash)

        string_key = key.to_s
        return ext[string_key] if ext.key?(string_key)

        symbol_key = key.to_sym
        return ext[symbol_key] if ext.key?(symbol_key)

        nil
      end

      def coerce_js_number(value)
        case value
        when nil
          0.0
        when true
          1.0
        when false
          0.0
        when Numeric
          value.to_f
        when String
          s = value.strip
          return 0.0 if s.empty?

          Float(s)
        else
          s = value.to_s.strip
          return 0.0 if s.empty?

          Float(s)
        end
      rescue ArgumentError, TypeError
        Float::NAN
      end
    end
  end
end
