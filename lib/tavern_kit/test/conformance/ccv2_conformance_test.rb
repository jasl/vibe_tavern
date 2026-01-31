# frozen_string_literal: true

require "test_helper"

class Ccv2ConformanceTest < Minitest::Test
  # Derived from: `resources/tavern_kit/docs/CONFORMANCE_RULES.yml` (ccv2.*)

  def minimal_ccv2_hash(**data_overrides)
    {
      "spec" => "chara_card_v2",
      "spec_version" => "2.0",
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
      }.merge(data_overrides),
    }
  end

  def test_detects_ccv2_by_spec
    assert_equal :v2, TavernKit::CharacterCard.detect_version(minimal_ccv2_hash)
  end

  def test_load_accepts_symbol_keys
    character = TavernKit::CharacterCard.load(minimal_ccv2_hash.transform_keys(&:to_sym))
    assert_equal "Alice", character.data.name
  end

  def test_requires_data_object
    hash = { "spec" => "chara_card_v2", "spec_version" => "2.0" }

    assert_raises(TavernKit::InvalidCardError) do
      TavernKit::CharacterCard.load(hash)
    end
  end

  def test_preserves_extensions_unknown_fields_on_roundtrip
    character = TavernKit::CharacterCard.load(minimal_ccv2_hash)
    exported = TavernKit::CharacterCard.export_v2(character)

    assert_equal({ "key" => "value" }, exported.dig("data", "extensions", "custom_app_data"))
  end

  def test_drops_unknown_data_keys_outside_extensions_on_export
    hash = minimal_ccv2_hash("unknown_key" => "drop-me")
    character = TavernKit::CharacterCard.load(hash)
    exported = TavernKit::CharacterCard.export_v2(character)

    refute exported.fetch("data").key?("unknown_key")
  end

  def test_preserves_character_book_unknown_fields
    hash = minimal_ccv2_hash(
      "character_book" => {
        "entries" => [],
        "custom_field" => "preserved",
      }
    )
    character = TavernKit::CharacterCard.load(hash)
    exported = TavernKit::CharacterCard.export_v2(character)

    assert_equal "preserved", exported.dig("data", "character_book", "custom_field")
  end

  def test_export_v2_writes_spec_and_version
    character = TavernKit::CharacterCard.load(minimal_ccv2_hash)
    exported = TavernKit::CharacterCard.export_v2(character)

    assert_equal "chara_card_v2", exported["spec"]
    assert_equal "2.0", exported["spec_version"]
  end
end
