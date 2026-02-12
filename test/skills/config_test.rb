# frozen_string_literal: true

require_relative "test_helper"

class SkillsConfigTest < Minitest::Test
  def test_from_context_returns_disabled_when_missing
    cfg = TavernKit::VibeTavern::Tools::Skills::Config.from_context(nil)
    assert_equal false, cfg.enabled
  end

  def test_from_context_requires_store_when_enabled
    error =
      assert_raises(ArgumentError) do
        TavernKit::VibeTavern::Tools::Skills::Config.from_context(
          {
            skills: {
              enabled: true,
            },
          },
        )
      end
    assert_includes error.message, "skills.store is required"

    error =
      assert_raises(ArgumentError) do
        TavernKit::VibeTavern::Tools::Skills::Config.from_context(
          {
            skills: {
              enabled: true,
              store: Object.new,
            },
          },
        )
      end
    assert_includes error.message, "must be a Tools::Skills::Store"
  end

  def test_from_context_allows_no_store_when_disabled
    cfg =
      TavernKit::VibeTavern::Tools::Skills::Config.from_context(
        {
          skills: {
            enabled: false,
          },
        },
      )

    assert_equal false, cfg.enabled
    assert_nil cfg.store
  end
end
