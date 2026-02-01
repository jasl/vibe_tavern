# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Macro::V1EngineTest < Minitest::Test
  def test_expands_identity_macros
    engine = TavernKit::SillyTavern::Macro::V1Engine.new
    env = build_env

    out = engine.expand("{{char}}/{{user}}/{{persona}}", environment: env)
    assert_equal "Al/Bob/Persona text", out
  end

  def test_original_expands_only_once
    engine = TavernKit::SillyTavern::Macro::V1Engine.new
    env = build_env(original: "ORIG")

    out = engine.expand("a {{original}} b {{original}} c", environment: env)
    assert_equal "a ORIG b  c", out
  end

  def test_newline_and_trim
    engine = TavernKit::SillyTavern::Macro::V1Engine.new
    env = build_env

    assert_equal "a\nb", engine.expand("a{{newline}}b", environment: env)
    assert_equal "ab", engine.expand("a\n{{trim}}\nb", environment: env)
  end

  def test_comments_are_removed
    engine = TavernKit::SillyTavern::Macro::V1Engine.new
    env = build_env

    assert_equal "a  b", engine.expand("a {{// hidden}} b", environment: env)
  end

  def test_variable_macros
    engine = TavernKit::SillyTavern::Macro::V1Engine.new
    env = build_env

    out = engine.expand("x {{setvar::name::Bob}} y {{getvar::name}} z", environment: env)
    assert_equal "x  y Bob z", out

    out2 = engine.expand("{{hasvar::name}}", environment: env)
    assert_equal "true", out2

    deleted = engine.expand("{{deletevar::name}}", environment: env)
    assert_equal "", deleted

    out3 = engine.expand("{{hasvar::name}}", environment: env)
    assert_equal "false", out3
  end

  def test_global_variable_macros
    engine = TavernKit::SillyTavern::Macro::V1Engine.new
    env = build_env

    out = engine.expand("{{setglobalvar::g::3}}{{getglobalvar::g}}", environment: env)
    assert_equal "3", out

    out2 = engine.expand("{{incglobalvar::g}}", environment: env)
    assert_equal "4.0", out2
  end

  def test_outlet_macro
    engine = TavernKit::SillyTavern::Macro::V1Engine.new
    env = build_env(outlets: { "foo" => "BAR" })

    out = engine.expand("x {{outlet::foo}} y", environment: env)
    assert_equal "x BAR y", out
  end

  def test_pick_is_deterministic_for_same_input
    engine = TavernKit::SillyTavern::Macro::V1Engine.new
    env = build_env(content_hash: "chat-1")

    out1 = engine.expand("{{pick::a,b,c}}", environment: env)
    out2 = engine.expand("{{pick::a,b,c}}", environment: env)
    assert_equal out1, out2
  end

  def test_unknown_macros_are_preserved_by_default
    engine = TavernKit::SillyTavern::Macro::V1Engine.new
    env = build_env

    out = engine.expand("hello {{unknown}}", environment: env)
    assert_equal "hello {{unknown}}", out
  end

  def test_unknown_macros_can_be_removed
    engine = TavernKit::SillyTavern::Macro::V1Engine.new(unknown: :empty)
    env = build_env

    out = engine.expand("hello {{unknown}}", environment: env)
    assert_equal "hello ", out
  end

  def test_dynamic_macros_are_case_insensitive
    engine = TavernKit::SillyTavern::Macro::V1Engine.new
    env = build_env(extensions: { "X" => "1" })

    out = engine.expand("{{x}}", environment: env)
    assert_equal "1", out
  end

  private

  def build_env(**overrides)
    char = TavernKit::Character.create(name: "Alice", nickname: "Al", description: "Desc", personality: "Pers", scenario: "Scen")
    user = TavernKit::User.new(name: "Bob", persona: "Persona text")

    defaults = {
      character: char,
      user: user,
      variables: TavernKit::VariablesStore::InMemory.new,
      outlets: {},
      original: nil,
      clock: -> { Time.utc(2020, 1, 1, 0, 0, 0) },
      rng: Random.new(1234),
      content_hash: nil,
      extensions: {},
      post_process: ->(s) { s },
    }

    TavernKit::SillyTavern::Macro::Environment.new(**defaults.merge(overrides))
  end
end
