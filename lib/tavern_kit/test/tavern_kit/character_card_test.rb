# frozen_string_literal: true

require "test_helper"

class TavernKit::CharacterCardTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../fixtures/files", __dir__)

  # --- Version Detection ---

  def test_detect_v2
    hash = { "spec" => "chara_card_v2", "spec_version" => "2.0", "data" => {} }
    assert_equal :v2, TavernKit::CharacterCard.detect_version(hash)
  end

  def test_detect_v3
    hash = { "spec" => "chara_card_v3", "spec_version" => "3.0", "data" => {} }
    assert_equal :v3, TavernKit::CharacterCard.detect_version(hash)
  end

  def test_detect_v1
    hash = { "name" => "Test", "description" => "Desc", "first_mes" => "Hello!" }
    assert_equal :v1, TavernKit::CharacterCard.detect_version(hash)
  end

  def test_detect_unknown
    assert_equal :unknown, TavernKit::CharacterCard.detect_version({})
    assert_equal :unknown, TavernKit::CharacterCard.detect_version("not a hash")
    assert_equal :unknown, TavernKit::CharacterCard.detect_version({ "spec" => "other" })
  end

  # --- Loading V2 ---

  def test_load_v2_hash
    hash = v2_card_hash(name: "Seraphina", description: "An angel")
    character = TavernKit::CharacterCard.load(hash)

    assert_kind_of TavernKit::Character, character
    assert_equal "Seraphina", character.name
    assert_equal "An angel", character.data.description
    assert_equal :v2, character.source_version
    assert character.v2?
    refute character.v3?
  end

  def test_load_v2_sets_defaults
    hash = v2_card_hash(name: "Test")
    character = TavernKit::CharacterCard.load(hash)

    assert_equal [], character.data.alternate_greetings
    assert_equal [], character.data.tags
    assert_equal({}, character.data.extensions)
    assert_equal "", character.data.creator
    assert_equal "", character.data.character_version
    # V3 fields default
    assert_equal [], character.data.group_only_greetings
    assert_nil character.data.assets
    assert_nil character.data.nickname
  end

  def test_load_v2_preserves_raw
    hash = v2_card_hash(name: "Test")
    character = TavernKit::CharacterCard.load(hash)

    assert_equal hash, character.raw
  end

  def test_load_v2_missing_data_raises
    hash = { "spec" => "chara_card_v2", "spec_version" => "2.0" }
    assert_raises(TavernKit::InvalidCardError) { TavernKit::CharacterCard.load(hash) }
  end

  def test_load_v2_empty_name_raises
    hash = v2_card_hash(name: "")
    assert_raises(TavernKit::InvalidCardError) { TavernKit::CharacterCard.load(hash) }
  end

  def test_load_v2_whitespace_name_raises
    hash = v2_card_hash(name: "   ")
    assert_raises(TavernKit::InvalidCardError) { TavernKit::CharacterCard.load(hash) }
  end

  # --- Loading V3 ---

  def test_load_v3_hash
    hash = v3_card_hash(
      name: "Seraphina",
      nickname: "Sera",
      group_only_greetings: ["Hi group!"],
    )
    character = TavernKit::CharacterCard.load(hash)

    assert_equal "Seraphina", character.name
    assert_equal "Sera", character.data.nickname
    assert_equal ["Hi group!"], character.data.group_only_greetings
    assert_equal :v3, character.source_version
    assert character.v3?
  end

  def test_load_v3_with_assets
    assets = [{ "type" => "icon", "uri" => "embeded://avatar.png", "name" => "avatar", "ext" => "png" }]
    hash = v3_card_hash(name: "Test", assets: assets)
    character = TavernKit::CharacterCard.load(hash)

    assert_equal assets, character.data.assets
  end

  def test_load_v3_with_dates
    hash = v3_card_hash(
      name: "Test",
      creation_date: "1706745600",
      modification_date: "1706832000",
    )
    character = TavernKit::CharacterCard.load(hash)

    assert_equal 1_706_745_600, character.data.creation_date
    assert_equal 1_706_832_000, character.data.modification_date
  end

  # --- Loading V1 ---

  def test_load_v1_raises
    hash = { "name" => "Test", "description" => "Desc", "first_mes" => "Hello!" }
    assert_raises(TavernKit::UnsupportedVersionError) { TavernKit::CharacterCard.load(hash) }
  end

  def test_load_unsupported_input_type_raises
    assert_raises(ArgumentError) { TavernKit::CharacterCard.load(42) }
  end

  def test_load_unknown_format_raises
    hash = { "spec" => "unknown_spec", "data" => { "name" => "Test" } }
    assert_raises(TavernKit::InvalidCardError) { TavernKit::CharacterCard.load(hash) }
  end

  # --- Export V2 ---

  def test_export_v2_format
    character = TavernKit::Character.create(
      name: "ExportChar",
      description: "A brave warrior",
      first_mes: "Greetings!",
      tags: ["fantasy", "warrior"],
    )

    v2 = TavernKit::CharacterCard.export_v2(character)

    assert_equal "chara_card_v2", v2["spec"]
    assert_equal "2.0", v2["spec_version"]
    assert_equal "ExportChar", v2["data"]["name"]
    assert_equal "A brave warrior", v2["data"]["description"]
    assert_equal "Greetings!", v2["data"]["first_mes"]
    assert_equal ["fantasy", "warrior"], v2["data"]["tags"]
  end

  def test_export_v2_preserves_v3_fields_in_extensions
    character = TavernKit::Character.create(
      name: "V3Char",
      nickname: "V3Nick",
      group_only_greetings: ["Hi group!"],
      creation_date: 12_345,
    )

    v2 = TavernKit::CharacterCard.export_v2(character, preserve_v3_fields: true)
    extras = v2["data"]["extensions"]["cc_extractor/v3"]

    refute_nil extras
    assert_equal "V3Nick", extras["nickname"]
    assert_equal ["Hi group!"], extras["group_only_greetings"]
    assert_equal 12_345, extras["creation_date"]
  end

  def test_export_v2_without_preserving_v3_fields
    character = TavernKit::Character.create(name: "Test", nickname: "Nick")

    v2 = TavernKit::CharacterCard.export_v2(character, preserve_v3_fields: false)

    refute v2["data"]["extensions"].key?("cc_extractor/v3")
  end

  def test_export_v2_includes_character_book
    book = { "name" => "TestBook", "entries" => [] }
    character = TavernKit::Character.create(name: "Test", character_book: book)

    v2 = TavernKit::CharacterCard.export_v2(character)
    assert_equal "TestBook", v2["data"]["character_book"]["name"]
  end

  def test_export_v2_deep_copies_extensions
    ext = { "custom" => { "nested" => "value" } }
    character = TavernKit::Character.create(name: "Test", extensions: ext)

    v2 = TavernKit::CharacterCard.export_v2(character)
    v2["data"]["extensions"]["custom"]["nested"] = "modified"

    # Original should be unchanged
    assert_equal "value", character.data.extensions["custom"]["nested"]
  end

  # --- Export V3 ---

  def test_export_v3_format
    character = TavernKit::Character.create(
      name: "V3Export",
      nickname: "V3Nick",
      group_only_greetings: ["Hi!"],
      assets: [{ "type" => "icon", "uri" => "data:image/png;base64,abc" }],
      creation_date: 12_345,
      modification_date: 67_890,
      source: ["https://example.com"],
    )

    v3 = TavernKit::CharacterCard.export_v3(character)

    assert_equal "chara_card_v3", v3["spec"]
    assert_equal "3.0", v3["spec_version"]
    assert_equal "V3Export", v3["data"]["name"]
    assert_equal "V3Nick", v3["data"]["nickname"]
    assert_equal ["Hi!"], v3["data"]["group_only_greetings"]
    assert_equal 12_345, v3["data"]["creation_date"]
    assert_equal 67_890, v3["data"]["modification_date"]
    assert_equal ["https://example.com"], v3["data"]["source"]
  end

  def test_export_v3_omits_nil_optional_fields
    character = TavernKit::Character.create(name: "Minimal")

    v3 = TavernKit::CharacterCard.export_v3(character)

    refute v3["data"].key?("nickname")
    refute v3["data"].key?("assets")
    refute v3["data"].key?("source")
    refute v3["data"].key?("creation_date")
    refute v3["data"].key?("modification_date")
    # group_only_greetings is always included (required in V3)
    assert_equal [], v3["data"]["group_only_greetings"]
  end

  def test_export_v3_upgrades_lorebook
    book = {
      "name" => "TestBook",
      "entries" => [
        { "keys" => "key1,key2", "use_regex" => nil, "content" => "test" },
        { "keys" => ["key3"], "use_regex" => true, "content" => "test2" },
      ],
    }
    character = TavernKit::Character.create(name: "Test", character_book: book)

    v3 = TavernKit::CharacterCard.export_v3(character)
    entries = v3["data"]["character_book"]["entries"]

    # use_regex should be coerced to boolean
    assert_equal false, entries[0]["use_regex"]
    assert_equal true, entries[1]["use_regex"]
    # entries should have extensions hash
    assert_kind_of Hash, entries[0]["extensions"]
  end

  # --- Round-trip ---

  def test_v2_roundtrip
    original = TavernKit::Character.create(
      name: "RoundTrip",
      description: "A test character",
      personality: "Brave",
      scenario: "Fantasy world",
      first_mes: "Hello, adventurer!",
      mes_example: "<START>\n{{user}}: Hi\n{{char}}: Hello!",
      creator_notes: "Test card",
      system_prompt: "You are a brave warrior.",
      post_history_instructions: "[Write in character]",
      alternate_greetings: ["Alt greeting 1"],
      tags: ["test"],
      creator: "TestCreator",
      character_version: "1.0",
    )

    v2_hash = TavernKit::CharacterCard.export_v2(original, preserve_v3_fields: false)
    reloaded = TavernKit::CharacterCard.load(v2_hash)

    assert_equal original.name, reloaded.name
    assert_equal original.data.description, reloaded.data.description
    assert_equal original.data.personality, reloaded.data.personality
    assert_equal original.data.scenario, reloaded.data.scenario
    assert_equal original.data.first_mes, reloaded.data.first_mes
    assert_equal original.data.mes_example, reloaded.data.mes_example
    assert_equal original.data.creator_notes, reloaded.data.creator_notes
    assert_equal original.data.system_prompt, reloaded.data.system_prompt
    assert_equal original.data.post_history_instructions, reloaded.data.post_history_instructions
    assert_equal original.data.alternate_greetings, reloaded.data.alternate_greetings
    assert_equal original.data.tags, reloaded.data.tags
    assert_equal original.data.creator, reloaded.data.creator
    assert_equal original.data.character_version, reloaded.data.character_version
  end

  def test_v3_roundtrip
    original = TavernKit::Character.create(
      name: "V3RoundTrip",
      description: "A V3 character",
      nickname: "V3Nick",
      group_only_greetings: ["Group hello!"],
      creation_date: 1_706_745_600,
      modification_date: 1_706_832_000,
      source: ["https://example.com"],
    )

    v3_hash = TavernKit::CharacterCard.export_v3(original)
    reloaded = TavernKit::CharacterCard.load(v3_hash)

    assert_equal original.name, reloaded.name
    assert_equal original.data.nickname, reloaded.data.nickname
    assert_equal original.data.group_only_greetings, reloaded.data.group_only_greetings
    assert_equal original.data.creation_date, reloaded.data.creation_date
    assert_equal original.data.modification_date, reloaded.data.modification_date
    assert_equal original.data.source, reloaded.data.source
    assert_equal :v3, reloaded.source_version
  end

  # --- PNG round-trip ---

  def test_png_roundtrip
    character = TavernKit::Character.create(
      name: "PNGChar",
      description: "Character in PNG",
      first_mes: "Hello from PNG!",
      nickname: "Pong",
    )

    output_path = File.join(FIXTURES_DIR, "test_roundtrip_#{object_id}.png")
    TavernKit::CharacterCard.write_to_png(
      character,
      input_png: File.join(FIXTURES_DIR, "base.png"),
      output_png: output_path,
      format: :both,
    )

    # Reload from PNG via Png::Parser (file ingestion lives outside core).
    hash = TavernKit::Png::Parser.extract_card_payload(output_path)
    reloaded = TavernKit::CharacterCard.load(hash)

    # V3 is preferred (ccv3 keyword)
    assert_equal :v3, reloaded.source_version
    assert_equal "PNGChar", reloaded.name
    assert_equal "Character in PNG", reloaded.data.description
    assert_equal "Hello from PNG!", reloaded.data.first_mes
    assert_equal "Pong", reloaded.data.nickname
  ensure
    File.delete(output_path) if output_path && File.exist?(output_path)
  end

  def test_load_hash_convenience
    hash = v2_card_hash(name: "HashLoad")
    character = TavernKit::CharacterCard.load_hash(hash)
    assert_equal "HashLoad", character.name
  end

  private

  def v2_card_hash(name:, **fields)
    {
      "spec" => "chara_card_v2",
      "spec_version" => "2.0",
      "data" => {
        "name" => name,
        "description" => fields[:description] || "",
        "personality" => fields[:personality] || "",
        "scenario" => fields[:scenario] || "",
        "first_mes" => fields[:first_mes] || "",
        "mes_example" => fields[:mes_example] || "",
        "creator_notes" => fields[:creator_notes] || "",
        "system_prompt" => fields[:system_prompt] || "",
        "post_history_instructions" => fields[:post_history_instructions] || "",
        "alternate_greetings" => fields[:alternate_greetings] || [],
        "tags" => fields[:tags] || [],
        "creator" => fields[:creator] || "",
        "character_version" => fields[:character_version] || "",
        "extensions" => fields[:extensions] || {},
      }.compact,
    }
  end

  def v3_card_hash(name:, **fields)
    data = {
      "name" => name,
      "description" => fields[:description] || "",
      "personality" => fields[:personality] || "",
      "scenario" => fields[:scenario] || "",
      "first_mes" => fields[:first_mes] || "",
      "mes_example" => fields[:mes_example] || "",
      "creator_notes" => fields[:creator_notes] || "",
      "system_prompt" => fields[:system_prompt] || "",
      "post_history_instructions" => fields[:post_history_instructions] || "",
      "alternate_greetings" => fields[:alternate_greetings] || [],
      "tags" => fields[:tags] || [],
      "creator" => fields[:creator] || "",
      "character_version" => fields[:character_version] || "",
      "extensions" => fields[:extensions] || {},
      "group_only_greetings" => fields[:group_only_greetings] || [],
    }

    # Optional V3 fields
    data["nickname"] = fields[:nickname] if fields.key?(:nickname)
    data["assets"] = fields[:assets] if fields.key?(:assets)
    data["creator_notes_multilingual"] = fields[:creator_notes_multilingual] if fields.key?(:creator_notes_multilingual)
    data["source"] = fields[:source] if fields.key?(:source)
    data["creation_date"] = fields[:creation_date] if fields.key?(:creation_date)
    data["modification_date"] = fields[:modification_date] if fields.key?(:modification_date)

    {
      "spec" => "chara_card_v3",
      "spec_version" => "3.0",
      "data" => data,
    }
  end
end
