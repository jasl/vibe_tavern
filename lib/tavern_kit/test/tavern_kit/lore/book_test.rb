# frozen_string_literal: true

require "test_helper"

class TavernKit::Lore::BookTest < Minitest::Test
  def test_from_h_and_helpers
    book = TavernKit::Lore::Book.from_h(
      "name" => "Test",
      "scan_depth" => 3,
      "recursive_scanning" => true,
      "extensions" => { "x" => 1 },
      "entries" => [
        { "keys" => ["a"], "content" => "A", "enabled" => true, "constant" => true },
        { "keys" => ["b"], "content" => "B", "enabled" => false },
      ],
    )

    assert_equal "Test", book.name
    assert_equal 3, book.scan_depth
    assert book.recursive_scanning?
    assert_equal({ "x" => 1 }, book.extensions)

    assert_equal 2, book.entry_count
    assert_equal 1, book.enabled_entries.size
    assert_equal 1, book.constant_entries.size
  end
end
