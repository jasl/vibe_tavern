# frozen_string_literal: true

require "test_helper"

require "tempfile"
require "zip"

class TavernKit::IngestTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../../fixtures/files", __dir__)

  def test_ingest_png_keeps_original_path
    path = File.join(FIXTURES_DIR, "ccv3_over_chara.png")

    TavernKit::Ingest.open(path) do |bundle|
      assert_equal path, bundle.main_image_path
      assert bundle.character.v3?
      assert_nil bundle.tmpdir
      assert_equal [], bundle.files
      assert_equal [], bundle.assets
    end
  end

  def test_ingest_byaf_normalizes_scenarios
    path = File.join(FIXTURES_DIR, "sample.byaf")

    TavernKit::Ingest.open(path) do |bundle|
      assert bundle.character.v2?
      assert_kind_of Array, bundle.scenarios
      assert_equal 2, bundle.scenarios.length

      scenario = bundle.scenarios.first
      assert scenario.key?("formatting_instructions")
      refute scenario.key?("formattingInstructions")

      assert_nil bundle.main_image_path
      assert_equal [], bundle.files
      assert_equal [], bundle.assets
    end
  end

  def test_ingest_byaf_extracts_assets_and_cleans_up
    zip_bytes = byaf_bytes(
      character_images: [
        { path: "images/portrait.png", label: "Default Portrait", content: "PNGDATA" },
      ],
      scenarios: [
        { title: "S1", background_path: "backgrounds/bg.png", background_content: "BGDATA" },
      ],
    )

    Tempfile.create(["bundle", ".byaf"]) do |f|
      f.binmode
      f.write(zip_bytes)
      f.flush

      tmpdir = nil
      main_image_path = nil
      extracted_paths = []

      TavernKit::Ingest.open(f.path) do |bundle|
        tmpdir = bundle.tmpdir
        main_image_path = bundle.main_image_path
        extracted_paths = bundle.files.map(&:path)

        assert Dir.exist?(tmpdir), "expected tmpdir to exist during block"
        assert File.file?(main_image_path)
        assert_equal 1, bundle.files.length
        assert_equal "PNGDATA", File.binread(main_image_path)
        assert_equal 2, bundle.assets.length
        bg = bundle.assets.find { |a| a.kind == :background_image }
        assert_equal "BGDATA", bg.read
        assert_match(/\Atavern_kit-byaf-/, File.basename(tmpdir))
      end

      refute Dir.exist?(tmpdir), "expected tmpdir to be cleaned up after block"
      extracted_paths.each do |p|
        refute File.exist?(p), "expected extracted file to be removed after block"
      end
      refute File.exist?(main_image_path), "expected main image to be removed after block"
    end
  end

  def test_ingest_charx_extracts_assets_and_cleans_up
    card_hash = TavernKit::CharacterCard.export_v3(TavernKit::Character.create(name: "ZipChar"))
    card_hash["data"]["assets"] = [
      { "type" => "icon", "uri" => "embeded://assets/icon.png", "name" => "main", "ext" => "png" },
      { "type" => "background", "uri" => "embeded://assets/bg.png", "name" => "scene", "ext" => "png" },
    ]

    zip_bytes = charx_bytes(
      card_hash: card_hash,
      assets: { "assets/icon.png" => "PNGDATA", "assets/bg.png" => "BGDATA" },
    )

    Tempfile.create(["bundle", ".charx"]) do |f|
      f.binmode
      f.write(zip_bytes)
      f.flush

      tmpdir = nil
      main_image_path = nil
      extracted_paths = []

      TavernKit::Ingest.open(f.path) do |bundle|
        tmpdir = bundle.tmpdir
        main_image_path = bundle.main_image_path
        extracted_paths = bundle.files.map(&:path)

        assert Dir.exist?(tmpdir)
        assert_equal "ZipChar", bundle.character.name
        assert File.file?(main_image_path)
        assert_equal 1, bundle.files.length
        assert_equal 2, bundle.assets.length
        bg = bundle.assets.find { |a| a.source_path == "assets/bg.png" }
        assert_equal "BGDATA", bg.read
      end

      refute Dir.exist?(tmpdir)
      extracted_paths.each { |p| refute File.exist?(p) }
      refute File.exist?(main_image_path)
    end
  end

  def test_ingest_byaf_asset_read_respects_max_bytes
    zip_bytes = byaf_bytes(
      character_images: [],
      scenarios: [
        { title: "S1", background_path: "backgrounds/bg.png", background_content: "BGDATA" },
      ],
    )

    Tempfile.create(["bundle", ".byaf"]) do |f|
      f.binmode
      f.write(zip_bytes)
      f.flush

      TavernKit::Ingest.open(f.path) do |bundle|
        bg = bundle.assets.find { |a| a.kind == :background_image }
        assert bg, "expected a background_image asset"

        err = assert_raises(TavernKit::Archive::ZipError) { bg.read(max_bytes: 2) }
        assert_match(/too large/i, err.message)
      end
    end
  end

  def test_ingest_charx_asset_read_respects_max_bytes
    card_hash = TavernKit::CharacterCard.export_v3(TavernKit::Character.create(name: "ZipChar"))
    card_hash["data"]["assets"] = [
      { "type" => "background", "uri" => "embeded://assets/bg.png", "name" => "scene", "ext" => "png" },
    ]

    zip_bytes = charx_bytes(
      card_hash: card_hash,
      assets: { "assets/bg.png" => "BGDATA" },
    )

    Tempfile.create(["bundle", ".charx"]) do |f|
      f.binmode
      f.write(zip_bytes)
      f.flush

      TavernKit::Ingest.open(f.path) do |bundle|
        assert_equal "ZipChar", bundle.character.name

        bg = bundle.assets.find { |a| a.source_path == "assets/bg.png" }
        assert bg, "expected bg asset"

        err = assert_raises(TavernKit::Archive::ZipError) { bg.read(max_bytes: 2) }
        assert_match(/too large/i, err.message)
      end
    end
  end

  private

  def byaf_bytes(character_images:, scenarios:)
    manifest = {
      "schemaVersion" => 1,
      "createdAt" => "2025-01-01T00:00:00Z",
      "characters" => ["characters/char1/character.json"],
      "scenarios" => scenarios.each_with_index.map { |_s, idx| "scenarios/s#{idx + 1}.json" },
    }

    character = {
      "schemaVersion" => 1,
      "id" => "char1",
      "name" => "alice",
      "displayName" => "Alice",
      "isNSFW" => false,
      "persona" => "Hello",
      "createdAt" => "2025-01-01T00:00:00Z",
      "updatedAt" => "2025-01-01T00:00:00Z",
      "loreItems" => [],
      "images" => character_images.map { |img| { "path" => img[:path], "label" => img[:label] } },
    }

    Zip::OutputStream.write_buffer do |out|
      out.put_next_entry("manifest.json")
      out.write(JSON.generate(manifest))

      out.put_next_entry("characters/char1/character.json")
      out.write(JSON.generate(character))

      character_images.each do |img|
        full = File.join("characters/char1", img[:path])
        out.put_next_entry(full)
        out.write(img[:content])
      end

      scenarios.each_with_index do |scenario, idx|
        out.put_next_entry("scenarios/s#{idx + 1}.json")
        out.write(
          JSON.generate(
            {
              "schemaVersion" => 1,
              "title" => scenario[:title],
              "formattingInstructions" => "Do X",
              "minP" => 0.1,
              "minPEnabled" => true,
              "temperature" => 1.0,
              "repeatPenalty" => 1.0,
              "repeatLastN" => 64,
              "topK" => 40,
              "topP" => 0.9,
              "exampleMessages" => [],
              "canDeleteExampleMessages" => true,
              "firstMessages" => [],
              "narrative" => "N",
              "promptTemplate" => "general",
              "grammar" => nil,
              "messages" => [],
              "backgroundImage" => scenario[:background_path],
            }
          )
        )

        out.put_next_entry(scenario[:background_path])
        out.write(scenario[:background_content])
      end
    end.string
  end

  def charx_bytes(card_hash:, assets:)
    Zip::OutputStream.write_buffer do |out|
      out.put_next_entry("card.json")
      out.write(JSON.generate(card_hash))

      assets.each do |path, content|
        out.put_next_entry(path)
        out.write(content)
      end
    end.string
  end
end
