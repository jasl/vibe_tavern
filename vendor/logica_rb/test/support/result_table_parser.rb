# frozen_string_literal: true

module ResultTableParser
  module_function

  # Parses upstream Logica ASCII table output:
  #
  # +------+------+
  # | col0 | col1 |
  # +------+------+
  # | 1    | a    |
  # +------+------+
  #
  # Returns:
  # { "columns" => ["col0", "col1"], "rows" => [["1", "a"]] }
  #
  # - Ignores blank lines and border lines
  # - Treats "NULL" as nil
  # - Keeps all other values as strings (no numeric coercion)
  def parse(text)
    row_lines =
      text
        .to_s
        .lines
        .map { |l| l.chomp.strip }
        .reject(&:empty?)
        .select { |l| l.start_with?("|") && l.end_with?("|") }

    return { "columns" => [], "rows" => [] } if row_lines.empty?

    header = split_row(row_lines.shift)
    rows = row_lines.map { |line| split_row(line).map { |v| v == "NULL" ? nil : v } }

    { "columns" => header, "rows" => rows }
  end

  def split_row(line)
    parts = line.to_s.split("|", -1)
    parts = parts[1..-2] || []
    parts.map { |p| p.strip }
  end
  private_class_method :split_row
end
