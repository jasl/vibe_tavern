# frozen_string_literal: true

require "test_helper"

class StCharacterCardsTest < Minitest::Test
  def pending!(reason)
    skip("Pending ST parity: #{reason}")
  end

  def test_png_read_prefers_ccv3
    pending!("PNG metadata read prefers ccv3 over chara")

    png = File.binread("test/fixtures/files/ccv3_over_chara.png")
    card = TavernKit::SillyTavern::CharacterCard.read_png(png)

    assert_equal "3.0", card.spec_version
  end

  def test_png_write_includes_chara_and_ccv3
    pending!("PNG write strips existing chunks and writes chara + ccv3")

    card = { "spec" => "chara_card_v2", "spec_version" => "2.0", "data" => { "name" => "Test" } }
    png = TavernKit::SillyTavern::CharacterCard.write_png(File.binread("test/fixtures/files/base.png"), card)

    assert TavernKit::SillyTavern::CharacterCard.png_has_chunk?(png, "chara")
    assert TavernKit::SillyTavern::CharacterCard.png_has_chunk?(png, "ccv3")
  end

  def test_byaf_macro_replacement
    pending!("BYAF replaces {user}/{character} and #{user}: syntax")

    byaf = TavernKit::SillyTavern::ByafParser.new(File.binread("test/fixtures/files/sample.byaf"))
    card = byaf.parse_character

    assert_includes card["data"]["first_mes"], "{{user}}"
    assert_includes card["data"]["first_mes"], "{{char}}"
  end
end
