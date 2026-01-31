# frozen_string_literal: true

require "test_helper"

class RisuaiTemplateCardsTest < Minitest::Test
  # Characterization source:
  # resources/Risuai/src/ts/process/index.svelte.ts (positionParser + promptTemplate assembly)

  def lore_entry(content:, position:, role: "system", depth: 0, inject: nil)
    ext = { "risuai" => { "role" => role, "depth" => depth } }
    ext["risuai"]["inject"] = inject if inject

    TavernKit::Lore::Entry.new(
      keys: ["k"],
      content: content,
      insertion_order: 100,
      enabled: true,
      position: position,
      extensions: ext,
    )
  end

  def test_position_placeholder_and_inject_at_location
    template = [
      { "type" => "plain", "type2" => "main", "role" => "system", "text" => "MAIN {{position::lorebook}}" },
      { "type" => "lorebook" },
      { "type" => "postEverything" },
    ]

    lore_entries = [
      lore_entry(content: "P1", position: "pt_lorebook"),
      lore_entry(
        content: "INJECT",
        position: "",
        inject: { "operation" => "append", "location" => "main", "param" => "", "lore" => false },
      ),
      lore_entry(content: "L1", position: ""),
      lore_entry(content: "DEPTH0", position: "depth", depth: 0),
    ]

    blocks = TavernKit::RisuAI::TemplateCards.assemble(template: template, groups: {}, lore_entries: lore_entries)

    assert_equal "MAIN P1 INJECT", blocks[0].content
    assert_equal "L1", blocks[1].content
    assert_equal "DEPTH0", blocks[2].content
  end

  def test_description_lore_positions
    template = [
      { "type" => "description" },
    ]

    groups = { description: [{ role: :system, content: "DESC" }] }

    lore_entries = [
      lore_entry(content: "BEFORE", position: "before_desc"),
      lore_entry(content: "AFTER", position: "after_desc"),
    ]

    blocks = TavernKit::RisuAI::TemplateCards.assemble(template: template, groups: groups, lore_entries: lore_entries)

    assert_equal ["BEFORE", "DESC", "AFTER"], blocks.map(&:content)
  end

  def test_author_note_inner_format_uses_default_text
    template = [
      { "type" => "authornote", "innerFormat" => "----\n{{slot}}", "defaultText" => "DEFAULT" },
    ]

    blocks = TavernKit::RisuAI::TemplateCards.assemble(template: template, groups: {}, lore_entries: [])

    assert_equal ["----\nDEFAULT"], blocks.map(&:content)
  end
end
