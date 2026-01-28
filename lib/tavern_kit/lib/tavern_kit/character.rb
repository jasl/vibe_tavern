# frozen_string_literal: true

require_relative "participant"
require_relative "character/schema"

module TavernKit
  # Unified character model representing a roleplay character.
  #
  # This is the canonical internal representation that supports all fields
  # from both Character Card V2 and V3 specifications (V3 is a superset of V2).
  #
  # Design principle: "strict in, strict out" - requires spec-compliant input
  # and exports spec-compliant data.
  #
  # Implements the {Participant} interface, allowing a Character to act as the
  # "user" in pure AI-to-AI conversations.
  #
  # @example Load a character
  #   character = TavernKit::CharacterCard.load("card.png")
  #   character.data.name  # => "Seraphina"
  #
  # @example Use a Character as User (AI-to-AI conversation)
  #   alice = TavernKit::CharacterCard.load("alice.png")
  #   bob = TavernKit::CharacterCard.load("bob.png")
  #
  #   plan = TavernKit.build(pipeline: TavernKit::SillyTavern::Pipeline) do
  #     character alice
  #     user bob  # Character implements Participant interface
  #     message "Hello!"
  #   end
  #
  # @see Participant
  # @see https://github.com/malfoyslastname/character-card-spec-v2
  # @see https://github.com/kwaroran/character-card-spec-v3
  class Character
    include Participant

    # Immutable character data value object (Ruby 3.2+ Data class).
    #
    # Contains all fields from V2 and V3 specs:
    #
    # V2 fields:
    # - name (required) - Character's display name
    # - description - Character's description/backstory
    # - personality - Character's personality traits
    # - scenario - The roleplay scenario/setting
    # - first_mes - First message (greeting)
    # - mes_example - Example dialogue
    # - creator_notes - Notes from the card creator
    # - system_prompt - Custom system prompt override
    # - post_history_instructions - Jailbreak/PHI content
    # - alternate_greetings - Array of alternative first messages
    # - character_book - Embedded lorebook/world info
    # - tags - Array of tags for categorization
    # - creator - Card creator's name
    # - character_version - Version string for the character
    # - extensions - Hash for storing extension data (must preserve unknown keys)
    #
    # V3 additions:
    # - group_only_greetings - Greetings only shown in group chats
    # - assets - Array of asset objects (images, etc.)
    # - nickname - Character's nickname
    # - creator_notes_multilingual - Localized creator notes
    # - source - Array of source URLs/references
    # - creation_date - Unix timestamp of creation
    # - modification_date - Unix timestamp of last modification
    Data = Data.define(
      # V2 base fields
      :name,
      :description,
      :personality,
      :scenario,
      :first_mes,
      :mes_example,
      :creator_notes,
      :system_prompt,
      :post_history_instructions,
      :alternate_greetings,
      :character_book,
      :tags,
      :creator,
      :character_version,
      :extensions,
      # V3 additions
      :group_only_greetings,
      :assets,
      :nickname,
      :creator_notes_multilingual,
      :source,
      :creation_date,
      :modification_date,
    )

    attr_reader :data, :source_version, :raw

    # @param data [Character::Data] the character data
    # @param source_version [Symbol, nil] :v2, :v3, or nil if created programmatically
    # @param raw [Hash, nil] the original raw hash (for debugging/round-tripping)
    def initialize(data:, source_version: nil, raw: nil)
      @data = data
      @source_version = source_version
      @raw = raw
    end

    # Create a Character with default/empty values.
    #
    # @param name [String] required character name
    # @param kwargs [Hash] optional field overrides
    # @return [Character]
    def self.create(name:, **kwargs)
      data = Data.new(
        name: name,
        description: kwargs[:description],
        personality: kwargs[:personality],
        scenario: kwargs[:scenario],
        first_mes: kwargs[:first_mes],
        mes_example: kwargs[:mes_example],
        creator_notes: kwargs[:creator_notes] || "",
        system_prompt: kwargs[:system_prompt] || "",
        post_history_instructions: kwargs[:post_history_instructions] || "",
        alternate_greetings: kwargs[:alternate_greetings] || [],
        character_book: kwargs[:character_book],
        tags: kwargs[:tags] || [],
        creator: kwargs[:creator] || "",
        character_version: kwargs[:character_version] || "",
        extensions: kwargs[:extensions] || {},
        # V3 fields
        group_only_greetings: kwargs[:group_only_greetings] || [],
        assets: kwargs[:assets],
        nickname: kwargs[:nickname],
        creator_notes_multilingual: kwargs[:creator_notes_multilingual],
        source: kwargs[:source],
        creation_date: kwargs[:creation_date],
        modification_date: kwargs[:modification_date],
      )

      new(data: data, source_version: nil, raw: nil)
    end

    # Check if this character was loaded from a V2 card.
    #
    # @return [Boolean]
    def v2?
      source_version == :v2
    end

    # Check if this character was loaded from a V3 card.
    #
    # @return [Boolean]
    def v3?
      source_version == :v3
    end

    # Delegate common data accessors for convenience.
    def name
      data.name
    end

    # Returns the character's persona text for use as a participant.
    #
    # Combines description and personality fields to provide a comprehensive
    # persona representation. This enables using a Character as the "user"
    # in AI-to-AI conversations.
    #
    # @return [String] combined description and personality text
    def persona_text
      parts = [data.description, data.personality]
        .compact
        .map(&:to_s)
        .reject(&:empty?)

      parts.join("\n\n")
    end

    # Returns the display name (nickname if present, otherwise name).
    # CCv3 specifies that {{char}} macro should use nickname when available.
    #
    # @return [String]
    def display_name
      nickname = data.nickname.to_s
      nickname.empty? ? data.name : nickname
    end

    # Convert to a hash compatible with CCv2/V3 spec.
    #
    # @return [Hash]
    def to_h
      {
        name: data.name,
        description: data.description,
        personality: data.personality,
        scenario: data.scenario,
        first_mes: data.first_mes,
        mes_example: data.mes_example,
        creator_notes: data.creator_notes,
        system_prompt: data.system_prompt,
        post_history_instructions: data.post_history_instructions,
        alternate_greetings: data.alternate_greetings || [],
        character_book: data.character_book,
        tags: data.tags || [],
        creator: data.creator,
        character_version: data.character_version,
        extensions: data.extensions || {},
        group_only_greetings: data.group_only_greetings || [],
        assets: data.assets,
        nickname: data.nickname,
        creator_notes_multilingual: data.creator_notes_multilingual,
        source: data.source,
        creation_date: data.creation_date,
        modification_date: data.modification_date,
      }
    end

    # Generate JSON Schema for the character data.
    #
    # Uses the EasyTalk Schema definition for spec-compliant schema generation.
    #
    # @return [Hash] JSON Schema definition
    def self.json_schema
      Schema.json_schema
    end
  end
end
