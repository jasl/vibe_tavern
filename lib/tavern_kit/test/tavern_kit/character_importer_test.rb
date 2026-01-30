# frozen_string_literal: true

require "test_helper"

require "tempfile"
require "zip"

class TavernKit::CharacterImporterTest < Minitest::Test
  def test_load_json_file
    character = TavernKit::Character.create(name: "Test")
    hash = TavernKit::CharacterCard.export_v2(character)

    Tempfile.create(["character", ".json"]) do |f|
      f.write(JSON.generate(hash))
      f.flush

      loaded = TavernKit::CharacterImporter.load(f.path)
      assert_equal "Test", loaded.data.name
      assert_equal :v2, loaded.source_version
    end
  end

  def test_load_json_string_falls_back_to_character_card
    character = TavernKit::Character.create(name: "Inline")
    json = JSON.generate(TavernKit::CharacterCard.export_v2(character))

    loaded = TavernKit::CharacterImporter.load(json)
    assert_equal "Inline", loaded.data.name
  end

  def test_load_byaf_file
    loaded = TavernKit::CharacterImporter.load("test/fixtures/files/sample.byaf")
    assert loaded.v2?
  end

  def test_load_charx_file
    card_hash = TavernKit::CharacterCard.export_v3(TavernKit::Character.create(name: "ZipChar"))
    zip_bytes = Zip::OutputStream.write_buffer do |out|
      out.put_next_entry("card.json")
      out.write(JSON.generate(card_hash))
    end.string

    Tempfile.create(["character", ".charx"]) do |f|
      f.binmode
      f.write(zip_bytes)
      f.flush

      loaded = TavernKit::CharacterImporter.load(f.path)
      assert loaded.v3?
      assert_equal "ZipChar", loaded.name
    end
  end

  def test_register_extension_importer
    Tempfile.create(["character", ".testchar"]) do |f|
      f.write("ignored")
      f.flush

      TavernKit::CharacterImporter.register(".testchar") do |_path|
        TavernKit::Character.create(name: "FromImporter")
      end

      loaded = TavernKit::CharacterImporter.load(f.path)
      assert_equal "FromImporter", loaded.data.name
    end
  end
end
