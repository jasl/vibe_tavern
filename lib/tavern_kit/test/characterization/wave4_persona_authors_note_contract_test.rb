# frozen_string_literal: true

require "test_helper"

class Wave4PersonaAuthorsNoteContractTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../fixtures/silly_tavern/authors_note", __dir__)

  def pending!(reason)
    skip("Pending Wave 4 (Persona + Author's Note): #{reason}")
  end

  def test_persona_top_bottom_an_only_applies_when_authors_note_is_scheduled
    pending!("Stage 5 must mirror ST addPersonaDescriptionExtensionPrompt() semantics")

    data = JSON.parse(File.read(File.join(FIXTURES_DIR, "persona_and_authors_note.json")))

    # Contract summary:
    # - persona_position TOP_AN/BOTTOM_AN rewrites the Author's Note content,
    #   but ONLY on turns where Author's Note is scheduled to inject.
    # - on turns where Author's Note is NOT scheduled, persona MUST NOT be
    #   injected at all (no separate message).
    #
    # Source reference (ST staging):
    # - public/script.js#addPersonaDescriptionExtensionPrompt()
    _ = data
  end

  def test_persona_at_depth_injects_as_in_chat_message_regardless_of_authors_note_schedule
    pending!("Stage 5 must support persona_description_positions.AT_DEPTH as in-chat injection")

    data = JSON.parse(File.read(File.join(FIXTURES_DIR, "persona_and_authors_note.json")))

    # Contract summary:
    # - persona AT_DEPTH becomes an in-chat injection at `persona_depth`
    #   with role `persona_role`, and MUST be WI-scannable (allowWIScan=true in ST).
    _ = data
  end
end
