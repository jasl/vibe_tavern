# frozen_string_literal: true

require "test_helper"

require_relative "result_table_parser"

class ResultTableParserTest < Minitest::Test
  def test_parse_normal_table
    text = <<~TXT
      +------+--------------+
      | col0 | logica_value |
      +------+--------------+
      | 0    | 1            |
      | 1    | 5            |
      +------+--------------+
    TXT

    assert_equal(
      { "columns" => %w[col0 logica_value], "rows" => [["0", "1"], ["1", "5"]] },
      ResultTableParser.parse(text)
    )
  end

  def test_parse_empty_table
    text = <<~TXT
      +------+
      | col0 |
      +------+
    TXT

    assert_equal({ "columns" => ["col0"], "rows" => [] }, ResultTableParser.parse(text))
  end

  def test_parse_null_values
    text = <<~TXT
      +--------+------------+-----------------+
      | person |   phone    |      email      |
      +--------+------------+-----------------+
      | Peter  | 4251112222 | NULL            |
      | James  | NULL       | james@salem.org |
      +--------+------------+-----------------+
    TXT

    assert_equal(
      {
        "columns" => %w[person phone email],
        "rows" => [["Peter", "4251112222", nil], ["James", nil, "james@salem.org"]],
      },
      ResultTableParser.parse(text)
    )
  end

  def test_parse_values_with_spaces
    text = <<~TXT

      +-------------+----------------+
      | key         | value          |
      +-------------+----------------+
      | hello world |  spaced value  |
      +-------------+----------------+

    TXT

    assert_equal(
      { "columns" => %w[key value], "rows" => [["hello world", "spaced value"]] },
      ResultTableParser.parse(text)
    )
  end
end
