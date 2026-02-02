# frozen_string_literal: true

require "easy_talk"
require_relative "character_book_entry_schema"
require_relative "extensions_schema"

module TavernKit
  class Character
    # Schema for Character Book (Lorebook) objects.
    #
    # A character book is a collection of knowledge entries that can be
    # conditionally injected into prompts based on keyword matching.
    #
    # @see https://github.com/kwaroran/character-card-spec-v3
    class CharacterBookSchema
      include EasyTalk::Schema

      define_schema do
        title "Character Book"
        description "A lorebook containing conditional knowledge entries"

        property :name, T.nilable(String), optional: true,
          description: "Book name for identification"

        property :description, T.nilable(String), optional: true,
          description: "Book description or notes"

        property :scan_depth, T.nilable(Integer), optional: true,
          minimum: 0,
          description: "Number of recent messages to scan for keyword matches"

        property :token_budget, T.nilable(Integer), optional: true,
          minimum: 0,
          description: "Maximum tokens to allocate for lorebook content"

        property :recursive_scanning, T.nilable(T::Boolean), optional: true,
          description: "Scan activated entry content for additional keyword matches"

        property :extensions, ExtensionsSchema, optional: true,
          description: "Application-specific extension data (must preserve unknown keys)"

        property :entries, T::Array[CharacterBookEntrySchema],
          description: "Array of lorebook entries"
      end

      def recursive_scanning?
        recursive_scanning == true
      end

      def enabled_entries
        (entries || []).select(&:enabled)
      end

      def constant_entries
        (entries || []).select(&:constant?)
      end

      def empty?
        entries.nil? || entries.empty?
      end

      def entry_count
        (entries || []).size
      end
    end
  end
end
