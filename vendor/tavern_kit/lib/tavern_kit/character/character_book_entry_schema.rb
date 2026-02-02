# frozen_string_literal: true

require "easy_talk"
require_relative "extensions_schema"

module TavernKit
  class Character
    # Schema for Character Book (Lorebook) Entry objects.
    #
    # Entries are activated during prompt generation when their keywords
    # are matched in the scan buffer. Activated entries inject their content
    # into the prompt at the configured position.
    #
    # @see https://github.com/kwaroran/character-card-spec-v3
    class CharacterBookEntrySchema
      include EasyTalk::Schema

      define_schema do
        title "Character Book Entry"
        description "A single lorebook entry for character knowledge injection"

        property :keys, T::Array[String],
          description: "Primary activation keywords or regex patterns"

        property :content, String,
          description: "Content to inject into the prompt when entry is activated"

        property :extensions, ExtensionsSchema, optional: true,
          description: "Application-specific extension data (must preserve unknown keys)"

        property :enabled, T::Boolean, default: true,
          description: "Whether this entry is active"

        property :insertion_order, Integer, default: 100,
          description: "Insertion order (lower = earlier)"

        property :use_regex, T::Boolean, default: false,
          description: "When true, keys are treated as regex patterns (V3 required)"

        property :case_sensitive, T.nilable(T::Boolean), optional: true,
          description: "Whether key matching is case-sensitive"

        property :constant, T.nilable(T::Boolean), optional: true,
          description: "Always activate regardless of key matches"

        property :name, T.nilable(String), optional: true,
          description: "Entry name or memo for identification"

        property :priority, T.nilable(Integer), optional: true,
          description: "Priority for token budget trimming (higher = keep longer)"

        property :id, T.nilable(String), optional: true,
          description: "Unique entry identifier"

        property :comment, T.nilable(String), optional: true,
          description: "Entry comment or description"

        property :selective, T.nilable(T::Boolean), optional: true,
          description: "Enable secondary key matching"

        property :secondary_keys, T.nilable(T::Array[String]), optional: true,
          description: "Secondary activation keywords (requires selective=true)"

        property :position, T.nilable(String), optional: true,
          enum: %w[before_char after_char],
          description: "Insertion position relative to character definition"
      end

      def regex?
        use_regex == true
      end

      def constant?
        constant == true
      end

      def selective?
        selective == true && secondary_keys&.any?
      end

      def display_name
        comment_val = respond_to?(:comment) ? comment : nil
        name_val = respond_to?(:name) ? self.name : nil
        comment_val&.then { |c| c.to_s.strip.empty? ? nil : c } ||
          name_val&.then { |n| n.to_s.strip.empty? ? nil : n } ||
          keys&.first&.slice(0, 50) ||
          "Entry #{id}"
      end
    end
  end
end
