# frozen_string_literal: true

require "test_helper"

class TavernKit::Png::ParserTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../../fixtures/files", __dir__)

  def base_png_path
    File.join(FIXTURES_DIR, "base.png")
  end

  def test_extract_text_chunks_from_plain_png
    chunks = TavernKit::Png::Parser.extract_text_chunks(base_png_path)
    assert_kind_of Array, chunks
    assert_empty chunks
  end

  def test_invalid_png_raises_parse_error
    # Write a non-PNG file
    bad_path = File.join(FIXTURES_DIR, "not_a_png.dat")
    File.binwrite(bad_path, "this is not a png file")

    assert_raises(TavernKit::Png::ParseError) do
      TavernKit::Png::Parser.extract_text_chunks(bad_path)
    end
  ensure
    File.delete(bad_path) if File.exist?(bad_path)
  end

  def test_extract_card_payload_raises_when_no_card
    assert_raises(TavernKit::Png::ParseError) do
      TavernKit::Png::Parser.extract_card_payload(base_png_path)
    end
  end

  def test_extract_text_chunks_finds_chara_chunk
    card_hash = { "spec" => "chara_card_v2", "spec_version" => "2.0", "data" => { "name" => "Test" } }
    png_with_card = build_png_with_text_chunk("chara", card_hash)

    path = File.join(FIXTURES_DIR, "test_chara.png")
    File.binwrite(path, png_with_card)

    chunks = TavernKit::Png::Parser.extract_text_chunks(path)
    assert_equal 1, chunks.size
    assert_equal "chara", chunks.first[:keyword]
    assert_equal "tEXt", chunks.first[:chunk]
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_extract_card_payload_decodes_base64_json
    card_hash = { "spec" => "chara_card_v2", "spec_version" => "2.0",
                  "data" => { "name" => "Seraphina", "description" => "An angel" } }
    png_with_card = build_png_with_text_chunk("chara", card_hash)

    path = File.join(FIXTURES_DIR, "test_decode.png")
    File.binwrite(path, png_with_card)

    payload = TavernKit::Png::Parser.extract_card_payload(path)
    assert_equal "chara_card_v2", payload["spec"]
    assert_equal "Seraphina", payload["data"]["name"]
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_prefers_ccv3_over_chara
    v2_hash = { "spec" => "chara_card_v2", "spec_version" => "2.0",
                "data" => { "name" => "V2Name" } }
    v3_hash = { "spec" => "chara_card_v3", "spec_version" => "3.0",
                "data" => { "name" => "V3Name" } }

    png = build_png_with_multiple_text_chunks([
      { keyword: "chara", data: v2_hash },
      { keyword: "ccv3", data: v3_hash },
    ])

    path = File.join(FIXTURES_DIR, "test_prefer_ccv3.png")
    File.binwrite(path, png)

    payload = TavernKit::Png::Parser.extract_card_payload(path)
    assert_equal "chara_card_v3", payload["spec"]
    assert_equal "V3Name", payload["data"]["name"]
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_decode_card_json_handles_plain_json
    json_str = '{"spec":"chara_card_v2","data":{"name":"Test"}}'
    parsed = TavernKit::Png::Parser.decode_card_json(json_str)
    assert_equal "chara_card_v2", parsed["spec"]
  end

  def test_decode_card_json_handles_base64
    json_str = '{"spec":"chara_card_v2","data":{"name":"Test"}}'
    encoded = Base64.strict_encode64(json_str)
    parsed = TavernKit::Png::Parser.decode_card_json(encoded)
    assert_equal "chara_card_v2", parsed["spec"]
  end

  def test_decode_card_json_returns_nil_for_garbage
    assert_nil TavernKit::Png::Parser.decode_card_json("not json or base64")
  end

  private

  def build_chunk(type, data)
    data = data.b if data.respond_to?(:b)
    type = type.b if type.respond_to?(:b)
    len = [data.bytesize].pack("N")
    crc = [Zlib.crc32(type + data)].pack("N")
    len + type + data + crc
  end

  def build_png_with_text_chunk(keyword, json_hash)
    sig = "\x89PNG\r\n\x1a\n".b

    # IHDR
    ihdr_data = [1, 1, 8, 2, 0, 0, 0].pack("NNCCCCC")
    ihdr = build_chunk("IHDR", ihdr_data)

    # IDAT
    raw = "\x00\xFF\xFF\xFF"
    compressed = Zlib::Deflate.deflate(raw)
    idat = build_chunk("IDAT", compressed)

    # tEXt chunk with base64-encoded JSON
    base64_data = Base64.strict_encode64(JSON.generate(json_hash))
    text_data = "#{keyword}\x00#{base64_data}"
    text_chunk = build_chunk("tEXt", text_data)

    # IEND
    iend = build_chunk("IEND", "")

    sig + ihdr + idat + text_chunk + iend
  end

  def build_png_with_multiple_text_chunks(entries)
    sig = "\x89PNG\r\n\x1a\n".b

    # IHDR
    ihdr_data = [1, 1, 8, 2, 0, 0, 0].pack("NNCCCCC")
    ihdr = build_chunk("IHDR", ihdr_data)

    # IDAT
    raw = "\x00\xFF\xFF\xFF"
    compressed = Zlib::Deflate.deflate(raw)
    idat = build_chunk("IDAT", compressed)

    # Multiple tEXt chunks
    text_chunks = entries.map do |entry|
      base64_data = Base64.strict_encode64(JSON.generate(entry[:data]))
      text_data = "#{entry[:keyword]}\x00#{base64_data}"
      build_chunk("tEXt", text_data)
    end

    # IEND
    iend = build_chunk("IEND", "")

    sig + ihdr + idat + text_chunks.join + iend
  end
end
