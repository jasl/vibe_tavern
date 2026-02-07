# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/directives/parser"

class DirectivesParserTest < Minitest::Test
  def test_parse_json_handles_code_fences
    content = <<~TEXT
      ```json
      {"assistant_text":"ok","directives":[]}
      ```
    TEXT

    parsed = TavernKit::VibeTavern::Directives::Parser.parse_json(content)
    assert_equal true, parsed[:ok]
    assert_equal "ok", parsed[:value].fetch("assistant_text")
  end

  def test_parse_json_handles_xmlish_directives_tags
    content = <<~TEXT
      <directives>
      {"assistant_text":"ok","directives":[]}
      </directives>
    TEXT

    parsed = TavernKit::VibeTavern::Directives::Parser.parse_json(content)
    assert_equal true, parsed[:ok]
    assert_equal [], parsed[:value].fetch("directives")
  end

  def test_parse_json_extracts_first_object_from_surrounding_text
    content = <<~TEXT
      Here is the JSON:
      {"assistant_text":"ok","directives":[]}
      Thanks!
    TEXT

    parsed = TavernKit::VibeTavern::Directives::Parser.parse_json(content)
    assert_equal true, parsed[:ok]
    assert_equal "ok", parsed[:value].fetch("assistant_text")
  end
end
