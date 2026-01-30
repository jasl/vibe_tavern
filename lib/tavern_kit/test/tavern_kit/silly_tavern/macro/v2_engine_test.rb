# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Macro::V2EngineTest < Minitest::Test
  def test_expands_env_macros
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env = build_env

    out = engine.expand("{{char}}/{{user}}/{{persona}}", environment: env)
    assert_equal "Al/Bob/Persona text", out

    out2 = engine.expand("{{description}}/{{personality}}/{{scenario}}", environment: env)
    assert_equal "Desc/Pers/Scen", out2
  end

  def test_additional_env_macros
    engine = TavernKit::SillyTavern::Macro::V2Engine.new

    char =
      TavernKit::Character.create(
        name: "Alice",
        system_prompt: "SYS",
        post_history_instructions: "PHI",
        creator_notes: "NOTES",
        character_version: "1.2.3",
        mes_example: "Example",
        extensions: { "depth_prompt" => { "prompt" => "DEPTH" } },
      )

    env =
      build_env(
        character: char,
        group_not_muted: "Alice, Bob",
        not_char: "Bob",
        model: "gpt-test",
        is_mobile: true,
        main_api: "openai",
      )

    assert_equal "Alice, Bob", engine.expand("{{groupNotMuted}}", environment: env)
    assert_equal "Bob", engine.expand("{{notChar}}", environment: env)
    assert_equal "SYS", engine.expand("{{charPrompt}}", environment: env)
    assert_equal "PHI", engine.expand("{{charInstruction}}", environment: env)
    assert_equal "DEPTH", engine.expand("{{charDepthPrompt}}", environment: env)
    assert_equal "NOTES", engine.expand("{{charCreatorNotes}}", environment: env)
    assert_equal "NOTES", engine.expand("{{creatorNotes}}", environment: env)
    assert_equal "1.2.3", engine.expand("{{charVersion}}", environment: env)
    assert_equal "1.2.3", engine.expand("{{version}}", environment: env)
    assert_equal "gpt-test", engine.expand("{{model}}", environment: env)
    assert_equal "true", engine.expand("{{isMobile}}", environment: env)

    examples = engine.expand("{{mesExamples}}", environment: env)
    assert_includes examples, "<START>"
    assert_includes examples, "Example"
  end

  def test_newline_and_noop
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env = build_env

    assert_equal "a\nbc", engine.expand("a{{newline}}b{{noop}}c", environment: env)
  end

  def test_outlet_macro
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env = build_env(outlets: { "foo" => "BAR" })

    out = engine.expand("x {{outlet::foo}} y", environment: env)
    assert_equal "x BAR y", out
  end

  def test_input_and_max_prompt_macros
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env = build_env(input: "Hello", max_prompt: 2048)

    assert_equal "Hello", engine.expand("{{input}}", environment: env)
    assert_equal "2048", engine.expand("{{maxPrompt}}", environment: env)
  end

  def test_reverse_macro
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env = build_env

    assert_equal "cba", engine.expand("{{reverse::abc}}", environment: env)
  end

  def test_roll_macros_support_space_and_colon_syntax
    engine = TavernKit::SillyTavern::Macro::V2Engine.new

    out1 = engine.expand("{{roll 6}}", environment: build_env(rng: Random.new(1234)))
    out2 = engine.expand("{{roll: 6}}", environment: build_env(rng: Random.new(1234)))
    assert_equal out1, out2
    assert_includes %w[1 2 3 4 5 6], out1
  end

  def test_banned_macro_collects_words_for_textgen
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env = build_env(main_api: "textgenerationwebui", banned_words: [])

    assert_equal "", engine.expand(%({{banned::"delve"}}), environment: env)
    assert_equal ["delve"], env.platform_attrs["banned_words"]
  end

  def test_time_macros
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env = build_env(clock: -> { Time.utc(2020, 1, 1, 0, 0, 0) })

    assert_equal "January 1, 2020", engine.expand("{{date}}", environment: env)
    assert_equal "Wednesday", engine.expand("{{weekday}}", environment: env)
    assert_equal "00:00", engine.expand("{{isotime}}", environment: env)
    assert_equal "2020-01-01", engine.expand("{{isodate}}", environment: env)
    assert_equal "2020-01-01 00:00:00", engine.expand("{{datetimeformat::YYYY-MM-DD HH:mm:ss}}", environment: env)
    assert_equal "in 3 hours", engine.expand("{{timeDiff::2020-01-01 03:00:00::2020-01-01 00:00:00}}", environment: env)
  end

  def test_idle_duration_macro
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env =
      build_env(
        clock: -> { Time.utc(2020, 1, 1, 2, 0, 0) },
        chat: [
          { "is_user" => true, "is_system" => false, "send_date" => Time.utc(2020, 1, 1, 0, 0, 0) },
          { "is_user" => false, "is_system" => false, "send_date" => Time.utc(2020, 1, 1, 0, 10, 0) },
        ],
      )

    assert_equal "2 hours", engine.expand("{{idleDuration}}", environment: env)
  end

  def test_random_macro_is_seeded_by_rng
    engine = TavernKit::SillyTavern::Macro::V2Engine.new

    out1 = engine.expand("{{random::a,b,c}}", environment: build_env(rng: Random.new(1234)))
    out2 = engine.expand("{{random::a,b,c}}", environment: build_env(rng: Random.new(1234)))
    assert_equal out1, out2
    assert_includes %w[a b c], out1
  end

  def test_pick_is_deterministic_for_same_input
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env = build_env(content_hash: "chat-1")

    out1 = engine.expand("{{pick::a,b,c}}", environment: env)
    out2 = engine.expand("{{pick::a,b,c}}", environment: env)
    assert_equal out1, out2
    assert_includes %w[a b c], out1
  end

  def test_variable_macros
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env = build_env

    out = engine.expand("{{setvar::name::Bob}}{{getvar::name}}", environment: env)
    assert_equal "Bob", out

    assert_equal "true", engine.expand("{{hasvar::name}}", environment: env)
    assert_equal "false", engine.expand("{{deletevar::name}}{{hasvar::name}}", environment: env)
  end

  def test_variable_macros_add_and_inc_dec
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env = build_env

    assert_equal "2", engine.expand("{{setvar::n::1}}{{addvar::n::1}}{{getvar::n}}", environment: env)
    assert_equal "12", engine.expand("{{incvar::x}}{{incvar::x}}", environment: env)
    assert_equal "-1", engine.expand("{{decvar::y}}", environment: env)

    assert_equal "2", engine.expand("{{setglobalvar::g::1}}{{addglobalvar::g::1}}{{getglobalvar::g}}", environment: env)
    assert_equal "12", engine.expand("{{incglobalvar::gx}}{{incglobalvar::gx}}", environment: env)
    assert_equal "-1", engine.expand("{{decglobalvar::gy}}", environment: env)
  end

  def test_original_expands_only_once
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env = build_env(original: "ORIG")

    out = engine.expand("a {{original}} b {{original}} c", environment: env)
    assert_equal "a ORIG b  c", out
  end

  def test_unknown_macros_are_preserved_by_default
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env = build_env

    out = engine.expand("hello {{unknown}}", environment: env)
    assert_equal "hello {{unknown}}", out
  end

  private

  def build_env(**overrides)
    char = TavernKit::Character.create(name: "Alice", nickname: "Al", description: "Desc", personality: "Pers", scenario: "Scen")
    user = TavernKit::User.new(name: "Bob", persona: "Persona text")

    defaults = {
      character: char,
      user: user,
      variables: TavernKit::ChatVariables::InMemory.new,
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
