# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::ContextTemplateTest < Minitest::Test
  def test_with_returns_new_instance
    template = TavernKit::SillyTavern::ContextTemplate.new(preset: "A")
    other = template.with(preset: "B")

    refute_same template, other
    assert_equal "A", template.preset
    assert_equal "B", other.preset
  end

  def test_render_renders_only_known_fields_and_preserves_unknown_macros
    template = TavernKit::SillyTavern::ContextTemplate.new(
      story_string: "{{#if system}}{{system}}\n{{/if}}{{trim}}",
    )

    rendered = template.render(system: "SYS")
    assert_equal "SYS\n{{trim}}\n", rendered
  end

  def test_render_supports_lore_before_after_aliases
    template = TavernKit::SillyTavern::ContextTemplate.new(
      story_string: "{{loreBefore}}|{{loreAfter}}",
    )

    rendered = template.render(wiBefore: "A", wiAfter: "B")
    assert_equal "A|B\n", rendered
  end

  def test_from_st_json_accepts_name_key
    template = TavernKit::SillyTavern::ContextTemplate.from_st_json(
      {
        "name" => "MyPreset",
        "story_string" => "{{#if description}}{{description}}{{/if}}",
      },
    )

    assert_equal "MyPreset", template.preset
    assert_equal "", template.render(description: "")
    assert_equal "X\n", template.render(description: "X")
  end
end
