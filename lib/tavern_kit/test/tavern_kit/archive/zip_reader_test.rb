# frozen_string_literal: true

require "test_helper"
require "zip"

class TavernKit::Archive::ZipReaderTest < Minitest::Test
  def zip_bytes(entries)
    Zip::OutputStream.write_buffer do |out|
      entries.each do |path, content|
        out.put_next_entry(path)
        out.write(content)
      end
    end.string
  end

  def test_rejects_path_traversal_entries
    data = zip_bytes(
      {
        "../evil.txt" => "nope",
        "manifest.json" => "{}",
      },
    )

    err = assert_raises(TavernKit::Archive::ZipError) do
      TavernKit::Archive::ZipReader.open(data) { |zip| zip.read("../evil.txt") }
    end

    assert_match(/traversal/i, err.message)
  end

  def test_enforces_max_entries
    data = zip_bytes(
      {
        "a.txt" => "1",
        "b.txt" => "2",
      },
    )

    assert_raises(TavernKit::Archive::ZipError) do
      TavernKit::Archive::ZipReader.open(data, max_entries: 1) { |_| nil }
    end
  end

  def test_enforces_max_entry_bytes
    data = zip_bytes({ "a.txt" => "123456" })

    err = assert_raises(TavernKit::Archive::ZipError) do
      TavernKit::Archive::ZipReader.open(data, max_entry_bytes: 5) { |zip| zip.read("a.txt") }
    end

    assert_match(/too large/i, err.message)
  end

  def test_enforces_max_total_bytes_budget
    data = zip_bytes({ "a.txt" => "1234", "b.txt" => "5678" })

    err = assert_raises(TavernKit::Archive::ZipError) do
      TavernKit::Archive::ZipReader.open(data, max_total_bytes: 6) do |zip|
        zip.read("a.txt")
        zip.read("b.txt")
      end
    end

    assert_match(/budget exceeded/i, err.message)
  end

  def test_enforces_max_compression_ratio
    data = zip_bytes({ "a.txt" => ("a" * 50_000) })

    err = assert_raises(TavernKit::Archive::ZipError) do
      TavernKit::Archive::ZipReader.open(data, max_compression_ratio: 2) { |zip| zip.read("a.txt") }
    end

    assert_match(/compression ratio/i, err.message)
  end

  def test_read_json_raises_on_invalid_json
    data = zip_bytes({ "manifest.json" => "{not json" })

    err = assert_raises(TavernKit::Archive::ZipError) do
      TavernKit::Archive::ZipReader.open(data) { |zip| zip.read_json("manifest.json") }
    end

    assert_match(/not valid json/i, err.message)
  end
end
