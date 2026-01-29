# frozen_string_literal: true

require "test_helper"

class TavernKit::CharacterTest < Minitest::Test
  def test_character_create_with_name_only
    char = TavernKit::Character.create(name: "Seraphina")
    assert_equal "Seraphina", char.name
    assert_equal "Seraphina", char.data.name
    assert_nil char.source_version
    assert_nil char.raw
  end

  def test_character_create_defaults
    char = TavernKit::Character.create(name: "Test")
    assert_equal "", char.data.creator_notes
    assert_equal "", char.data.system_prompt
    assert_equal "", char.data.post_history_instructions
    assert_equal [], char.data.alternate_greetings
    assert_equal [], char.data.tags
    assert_equal "", char.data.creator
    assert_equal "", char.data.character_version
    assert_equal({}, char.data.extensions)
    assert_equal [], char.data.group_only_greetings
  end

  def test_character_create_with_all_v2_fields
    char = TavernKit::Character.create(
      name: "Seraphina",
      description: "A celestial being",
      personality: "Kind and wise",
      scenario: "A mystical forest",
      first_mes: "Hello, traveler!",
      mes_example: "<START>\n{{user}}: Hi\n{{char}}: Hello!",
      creator_notes: "Made with love",
      system_prompt: "You are Seraphina",
      post_history_instructions: "Stay in character",
      alternate_greetings: ["Greetings!", "Welcome!"],
      tags: ["fantasy", "angel"],
      creator: "author",
      character_version: "1.0",
      extensions: { talkativeness: 0.8 },
    )

    assert_equal "Seraphina", char.data.name
    assert_equal "A celestial being", char.data.description
    assert_equal "Kind and wise", char.data.personality
    assert_equal "A mystical forest", char.data.scenario
    assert_equal "Hello, traveler!", char.data.first_mes
    assert_equal "You are Seraphina", char.data.system_prompt
    assert_equal ["Greetings!", "Welcome!"], char.data.alternate_greetings
    assert_equal ["fantasy", "angel"], char.data.tags
    assert_equal "author", char.data.creator
    assert_equal({ talkativeness: 0.8 }, char.data.extensions)
  end

  def test_character_create_with_v3_fields
    char = TavernKit::Character.create(
      name: "Seraphina",
      nickname: "Sera",
      group_only_greetings: ["Hello, group!"],
      source: ["https://example.com"],
      creation_date: "1700000000",
      modification_date: "1700100000",
    )

    assert_equal "Sera", char.data.nickname
    assert_equal ["Hello, group!"], char.data.group_only_greetings
    assert_equal ["https://example.com"], char.data.source
    assert_equal 1700000000, char.data.creation_date
    assert_equal 1700100000, char.data.modification_date
  end

  def test_character_implements_participant
    char = TavernKit::Character.create(name: "Test")
    assert_kind_of TavernKit::Participant, char
  end

  def test_character_persona_text
    char = TavernKit::Character.create(
      name: "Test",
      description: "A brave warrior",
      personality: "Bold and fierce",
    )
    assert_equal "A brave warrior\n\nBold and fierce", char.persona_text
  end

  def test_character_persona_text_description_only
    char = TavernKit::Character.create(name: "Test", description: "A brave warrior")
    assert_equal "A brave warrior", char.persona_text
  end

  def test_character_persona_text_personality_only
    char = TavernKit::Character.create(name: "Test", personality: "Bold")
    assert_equal "Bold", char.persona_text
  end

  def test_character_persona_text_empty
    char = TavernKit::Character.create(name: "Test")
    assert_equal "", char.persona_text
  end

  def test_character_display_name_with_nickname
    char = TavernKit::Character.create(name: "Seraphina", nickname: "Sera")
    assert_equal "Sera", char.display_name
  end

  def test_character_display_name_without_nickname
    char = TavernKit::Character.create(name: "Seraphina")
    assert_equal "Seraphina", char.display_name
  end

  def test_character_display_name_empty_nickname
    char = TavernKit::Character.create(name: "Seraphina", nickname: "")
    assert_equal "Seraphina", char.display_name
  end

  def test_character_v2_v3_flags
    char_v2 = TavernKit::Character.new(
      data: TavernKit::Character::Data.new(
        name: "Test", description: nil, personality: nil, scenario: nil,
        first_mes: nil, mes_example: nil, creator_notes: "", system_prompt: "",
        post_history_instructions: "", alternate_greetings: [], character_book: nil,
        tags: [], creator: "", character_version: "", extensions: {},
        group_only_greetings: [], assets: nil, nickname: nil,
        creator_notes_multilingual: nil, source: nil, creation_date: nil,
        modification_date: nil,
      ),
      source_version: :v2,
    )
    assert char_v2.v2?
    refute char_v2.v3?

    char_v3 = TavernKit::Character.new(
      data: char_v2.data,
      source_version: :v3,
    )
    refute char_v3.v2?
    assert char_v3.v3?
  end

  def test_character_to_h
    char = TavernKit::Character.create(
      name: "Seraphina",
      description: "A celestial being",
      personality: "Kind",
    )
    h = char.to_h
    assert_equal "Seraphina", h[:name]
    assert_equal "A celestial being", h[:description]
    assert_equal "Kind", h[:personality]
    assert_equal [], h[:alternate_greetings]
    assert_equal [], h[:tags]
    assert_equal({}, h[:extensions])
    assert_equal [], h[:group_only_greetings]
  end

  def test_character_data_is_immutable
    char = TavernKit::Character.create(name: "Test")
    assert char.data.frozen?
  end

  def test_character_json_schema
    schema = TavernKit::Character.json_schema
    assert_kind_of Hash, schema
    # EasyTalk returns string-keyed hashes
    assert_equal "Character Card Data", schema["title"]
    assert schema["properties"].key?("name")
  end
end
