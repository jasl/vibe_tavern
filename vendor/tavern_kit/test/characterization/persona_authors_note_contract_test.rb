# frozen_string_literal: true

require "test_helper"

class PersonaAuthorsNoteContractTest < Minitest::Test
  # Upstream references:
  # - resources/SillyTavern/public/scripts/openai.js @ bba43f332
  #   - preparePromptsForChatCompletion() (Author's Note + persona positioning)
  # - docs/contracts/prompt-orchestration.md (TavernKit contract notes)
  FIXTURES_DIR = File.expand_path("../fixtures/silly_tavern/authors_note", __dir__)

  def test_persona_top_bottom_an_only_applies_when_authors_note_is_scheduled
    data = JSON.parse(File.read(File.join(FIXTURES_DIR, "persona_and_authors_note.json")))

    cases = Array(data.fetch("cases")).select do |c|
      %w[top_an bottom_an].include?(c.dig("persona", "position"))
    end

    cases.each do |test_case|
      an = test_case.fetch("authors_note")
      persona = test_case.fetch("persona")

      entry = TavernKit::SillyTavern::InjectionPlanner.authors_note_entry(
        turn_count: test_case.fetch("turn_count"),
        text: an.fetch("text"),
        frequency: an.fetch("frequency"),
        position: an.fetch("position"),
        depth: an.fetch("depth"),
        role: an.fetch("role"),
        persona_text: persona.fetch("text"),
        persona_position: persona.fetch("position"),
      )

      expected = test_case.fetch("expected")
      if expected.fetch("authors_note_injected")
        assert entry, test_case.fetch("name")
        assert_equal expected.fetch("authors_note_text"), entry.content, test_case.fetch("name")
      else
        assert_nil entry, test_case.fetch("name")
      end
    end
  end

  def test_persona_at_depth_injects_as_in_chat_message_regardless_of_authors_note_schedule
    data = JSON.parse(File.read(File.join(FIXTURES_DIR, "persona_and_authors_note.json")))

    test_case = Array(data.fetch("cases")).find { |c| c.dig("persona", "position") == "at_depth" }
    refute_nil test_case

    persona = test_case.fetch("persona")
    expected = test_case.fetch("expected")

    entry = TavernKit::SillyTavern::InjectionPlanner.persona_at_depth_entry(
      text: persona.fetch("text"),
      position: persona.fetch("position"),
      depth: persona.fetch("depth"),
      role: persona.fetch("role"),
    )

    assert entry, test_case.fetch("name")
    assert_equal :chat, entry.position
    assert_equal expected.fetch("persona_depth"), entry.depth
    assert_equal expected.fetch("persona_role").to_sym, entry.role
    assert entry.scan?
  end
end
