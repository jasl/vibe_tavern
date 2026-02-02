# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::ExpanderVarsTest < Minitest::Test
  def test_build_creates_environment_from_context
    character = TavernKit::Character.create(name: "Nyx")
    user = TavernKit::User.new(name: "Alice", persona: "A brave knight")

    ctx =
      TavernKit::Prompt::Context.new(
        character: character,
        user: user,
        user_message: "Hello!",
        outlets: { "wi" => "value" },
        macro_vars: { dynamic_macros: { "foo" => "bar" } },
        group: { members: ["Nyx", "Zara"], muted: ["Zara"] },
      )

    env = TavernKit::SillyTavern::ExpanderVars.build(ctx)

    assert_equal "Nyx", env.character_name
    assert_equal "Alice", env.user_name
    assert_equal "Nyx, Zara", env.group_name
    assert_equal "Hello!", env.original
    assert_equal "bar", env.dynamic_macros["foo"]

    assert_equal "Nyx", env.platform_attrs["group_not_muted"]
    assert_equal "Zara, Alice", env.platform_attrs["not_char"]
  end
end
