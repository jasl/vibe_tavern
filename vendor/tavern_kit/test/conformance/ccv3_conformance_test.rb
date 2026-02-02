# frozen_string_literal: true

require "test_helper"

class Ccv3ConformanceTest < Minitest::Test
  # Derived from:
  # - `resources/tavern_kit/docs/CONFORMANCE_RULES.yml` (ccv3.*)
  # - `resources/character-card-spec-v3/` (normative CCv3 fields)

  def minimal_ccv3_hash(**data_overrides)
    {
      "spec" => "chara_card_v3",
      "spec_version" => "3.0",
      "data" => {
        "name" => "Alice",
        "description" => "A friendly assistant.",
        "personality" => "Helpful and kind.",
        "scenario" => "You are chatting with Alice.",
        "first_mes" => "Hello!",
        "mes_example" => "<START>\n{{user}}: Hi\n{{char}}: Hello\n",
        "tags" => [],
        "creator" => "",
        "character_version" => "",
        "extensions" => { "custom_app_data" => { "key" => "value" } },
        "group_only_greetings" => [],
      }.merge(data_overrides),
    }
  end

  def test_detects_ccv3_by_spec
    assert_equal :v3, TavernKit::CharacterCard.detect_version(minimal_ccv3_hash)
  end

  def test_requires_data_object
    hash = { "spec" => "chara_card_v3", "spec_version" => "3.0" }

    assert_raises(TavernKit::InvalidCardError) do
      TavernKit::CharacterCard.load(hash)
    end
  end

  def test_requires_non_empty_name
    hash = minimal_ccv3_hash("name" => "  ")

    assert_raises(TavernKit::InvalidCardError) do
      TavernKit::CharacterCard.load(hash)
    end
  end

  def test_coerces_timestamp_fields_to_integers
    hash = minimal_ccv3_hash(
      "creation_date" => "1700000000",
      "modification_date" => 1_700_000_001,
    )

    character = TavernKit::CharacterCard.load(hash)
    assert_equal 1_700_000_000, character.data.creation_date
    assert_equal 1_700_000_001, character.data.modification_date

    exported = TavernKit::CharacterCard.export_v3(character)
    assert_equal 1_700_000_000, exported.dig("data", "creation_date")
    assert_equal 1_700_000_001, exported.dig("data", "modification_date")
  end

  def test_preserves_extensions_unknown_fields_on_roundtrip
    character = TavernKit::CharacterCard.load(minimal_ccv3_hash)
    exported = TavernKit::CharacterCard.export_v3(character)

    assert_equal({ "key" => "value" }, exported.dig("data", "extensions", "custom_app_data"))
  end

  def test_drops_unknown_data_keys_outside_extensions_on_export
    hash = minimal_ccv3_hash("unknown_key" => "drop-me")
    character = TavernKit::CharacterCard.load(hash)
    exported = TavernKit::CharacterCard.export_v3(character)

    refute exported.fetch("data").key?("unknown_key")
  end

  def test_export_v3_writes_spec_and_version
    character = TavernKit::CharacterCard.load(minimal_ccv3_hash)
    exported = TavernKit::CharacterCard.export_v3(character)

    assert_equal "chara_card_v3", exported["spec"]
    assert_equal "3.0", exported["spec_version"]
  end
end
