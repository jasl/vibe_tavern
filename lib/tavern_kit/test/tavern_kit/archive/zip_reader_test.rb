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
end
