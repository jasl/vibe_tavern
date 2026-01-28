# frozen_string_literal: true

require "test_helper"

class TavernKit::Png::WriterTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../../fixtures/files", __dir__)

  def base_png_path
    File.join(FIXTURES_DIR, "base.png")
  end

  def setup
    @output_path = File.join(FIXTURES_DIR, "test_output_#{object_id}.png")
    @character = TavernKit::Character.create(
      name: "TestChar",
      description: "A test character",
      first_mes: "Hello!",
    )
  end

  def teardown
    File.delete(@output_path) if File.exist?(@output_path)
  end

  def test_embed_character_creates_valid_png
    TavernKit::Png::Writer.embed_character(
      base_png_path, @output_path, @character, format: :both
    )

    assert File.exist?(@output_path)
    bytes = File.binread(@output_path)
    assert bytes.start_with?("\x89PNG\r\n\x1a\n".b)
  end

  def test_embed_character_v2_only
    TavernKit::Png::Writer.embed_character(
      base_png_path, @output_path, @character, format: :v2_only
    )

    chunks = TavernKit::Png::Parser.extract_text_chunks(@output_path)
    keywords = chunks.map { |c| c[:keyword] }

    assert_includes keywords, "chara"
    refute_includes keywords, "ccv3"
  end

  def test_embed_character_v3_only
    TavernKit::Png::Writer.embed_character(
      base_png_path, @output_path, @character, format: :v3_only
    )

    chunks = TavernKit::Png::Parser.extract_text_chunks(@output_path)
    keywords = chunks.map { |c| c[:keyword] }

    refute_includes keywords, "chara"
    assert_includes keywords, "ccv3"
  end

  def test_embed_character_both
    TavernKit::Png::Writer.embed_character(
      base_png_path, @output_path, @character, format: :both
    )

    chunks = TavernKit::Png::Parser.extract_text_chunks(@output_path)
    keywords = chunks.map { |c| c[:keyword] }

    assert_includes keywords, "chara"
    assert_includes keywords, "ccv3"
  end

  def test_embed_character_replaces_existing_chunks
    # First write
    TavernKit::Png::Writer.embed_character(
      base_png_path, @output_path, @character, format: :both
    )

    # Second write over the same file
    updated_char = TavernKit::Character.create(name: "UpdatedChar", first_mes: "Updated!")
    second_output = "#{@output_path}.second.png"
    begin
      TavernKit::Png::Writer.embed_character(
        @output_path, second_output, updated_char, format: :both
      )

      chunks = TavernKit::Png::Parser.extract_text_chunks(second_output)
      chara_chunks = chunks.select { |c| c[:keyword] == "chara" }
      ccv3_chunks = chunks.select { |c| c[:keyword] == "ccv3" }

      # Should have exactly one of each, not duplicates
      assert_equal 1, chara_chunks.size
      assert_equal 1, ccv3_chunks.size
    ensure
      File.delete(second_output) if File.exist?(second_output)
    end
  end

  def test_invalid_format_raises
    assert_raises(ArgumentError) do
      TavernKit::Png::Writer.embed_character(
        base_png_path, @output_path, @character, format: :invalid
      )
    end
  end

  def test_missing_input_file_raises
    assert_raises(TavernKit::Png::WriteError) do
      TavernKit::Png::Writer.embed_character(
        "/nonexistent/path.png", @output_path, @character
      )
    end
  end

  def test_invalid_input_png_raises
    bad_path = File.join(FIXTURES_DIR, "bad_png.dat")
    File.binwrite(bad_path, "not a png")

    assert_raises(TavernKit::Png::ParseError) do
      TavernKit::Png::Writer.embed_character(
        bad_path, @output_path, @character
      )
    end
  ensure
    File.delete(bad_path) if File.exist?(bad_path)
  end

  def test_build_text_chunk_format
    json_hash = { "key" => "value" }
    chunk_bytes = TavernKit::Png::Writer.build_text_chunk("test", json_hash)

    # Chunk format: length(4) + type(4) + data(N) + CRC(4)
    assert_kind_of String, chunk_bytes
    length = chunk_bytes[0, 4].unpack1("N")
    type = chunk_bytes[4, 4]
    assert_equal "tEXt", type

    # Data should be keyword + NUL + base64
    data = chunk_bytes[8, length]
    keyword, rest = data.split("\x00", 2)
    assert_equal "test", keyword
    decoded = JSON.parse(Base64.strict_decode64(rest))
    assert_equal "value", decoded["key"]
  end
end
