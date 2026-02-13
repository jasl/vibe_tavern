# frozen_string_literal: true

require_relative "test_helper"

class SkillsConfigTest < Minitest::Test
  def test_from_context_returns_disabled_when_missing
    cfg = TavernKit::VibeTavern::Tools::Skills::Config.from_context(nil)
    assert_equal false, cfg.enabled
    assert_equal :off, cfg.allowed_tools_enforcement
    assert_equal :ignore, cfg.allowed_tools_invalid_allowlist
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
    assert_equal :off, cfg.allowed_tools_enforcement
    assert_equal :ignore, cfg.allowed_tools_invalid_allowlist
  end

  def test_from_context_parses_allowed_tools_enforcement_and_invalid_allowlist
    store =
      Class.new(TavernKit::VibeTavern::Tools::Skills::Store) do
        def list_skills = []
        def load_skill(name:, max_bytes: nil) = raise NotImplementedError
        def read_skill_file(name:, rel_path:, max_bytes:) = raise NotImplementedError
      end.new

    cfg =
      TavernKit::VibeTavern::Tools::Skills::Config.from_context(
        {
          skills: {
            enabled: true,
            store: store,
            allowed_tools_enforcement: "enforce",
            allowed_tools_invalid_allowlist: :enforce,
          },
        },
      )

    assert_equal true, cfg.enabled
    assert_equal :enforce, cfg.allowed_tools_enforcement
    assert_equal :enforce, cfg.allowed_tools_invalid_allowlist
  end

  def test_from_context_forces_enforcement_off_when_skills_disabled
    cfg =
      TavernKit::VibeTavern::Tools::Skills::Config.from_context(
        {
          skills: {
            enabled: false,
            allowed_tools_enforcement: :enforce,
          },
        },
      )

    assert_equal false, cfg.enabled
    assert_equal :off, cfg.allowed_tools_enforcement
  end
end
