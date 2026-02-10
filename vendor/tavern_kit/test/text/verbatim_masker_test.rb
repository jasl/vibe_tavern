# frozen_string_literal: true

require "test_helper"

class TavernKit::Text::VerbatimMaskerTest < Minitest::Test
  def test_masks_verbatim_zones_and_applies_escape_hatch_outside_them
    text = "A `code \\<lang>` B \\<lang code=\"ja\">X\\</lang> C"

    masked, placeholders =
      TavernKit::Text::VerbatimMasker.mask(
        text,
        escape_hatch: { enabled: true, mode: :html_entity },
      )

    restored = TavernKit::Text::VerbatimMasker.unmask(masked, placeholders)

    assert_equal "A `code \\<lang>` B &lt;lang code=\"ja\">X&lt;/lang> C", restored
  end

  def test_escape_hatch_mode_literal
    text = "Hello \\<lang>ok\\</lang>."

    masked, placeholders =
      TavernKit::Text::VerbatimMasker.mask(
        text,
        escape_hatch: { enabled: true, mode: :literal },
      )

    restored = TavernKit::Text::VerbatimMasker.unmask(masked, placeholders)
    assert_equal "Hello <lang>ok</lang>.", restored
  end
end
