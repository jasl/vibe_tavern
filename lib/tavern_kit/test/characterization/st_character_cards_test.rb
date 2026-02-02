# frozen_string_literal: true

require "test_helper"

class StCharacterCardsTest < Minitest::Test
  # Upstream references:
  # - resources/SillyTavern/src/character-card-parser.js @ bba43f332
  #   - read(): prefer ccv3 over chara when both exist
  #   - write(): dual-write chara + ccv3 best-effort
  def test_png_read_prefers_ccv3
    TavernKit::Ingest.open("test/fixtures/files/ccv3_over_chara.png") do |bundle|
      assert bundle.character.v3?
    end
  end

  def test_png_write_includes_chara_and_ccv3
    output = Tempfile.new(["tavern_kit_st_write", ".png"])

    character = TavernKit::Character.create(name: "Test")
    TavernKit::Png::Writer.embed_character(
      "test/fixtures/files/ccv3_over_chara.png",
      output.path,
      character,
      format: :both,
    )

    chunks = TavernKit::Png::Parser.extract_text_chunks(output.path)
    keywords = chunks.map { |c| c[:keyword] }

    assert_includes keywords, "chara"
    assert_includes keywords, "ccv3"
    assert_equal 1, keywords.count { |k| k == "chara" }
    assert_equal 1, keywords.count { |k| k == "ccv3" }
  ensure
    output&.close!
  end

  def test_byaf_macro_replacement
    byaf = TavernKit::Archive::ByafParser.new(File.binread("test/fixtures/files/sample.byaf"))
    card = byaf.parse_character

    assert_includes card["data"]["first_mes"], "{{user}}"
    assert_includes card["data"]["first_mes"], "{{char}}"
  end
end
