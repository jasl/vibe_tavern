require "test_helper"

class VibeTavernOutputTagsTest < ActiveSupport::TestCase
  setup do
    TavernKit::VibeTavern::Pipeline
  end

  def build_config(output_tags_hash)
    runtime =
      TavernKit::PromptBuilder::Context.build(
        { output_tags: output_tags_hash },
        type: :app,
      )

    TavernKit::VibeTavern::OutputTags::Config.from_runtime(runtime)
  end

  test "does nothing when output tag processing is disabled" do
    config = build_config(enabled: false)

    input = %(Hello <lang code="ja">ありがとう</lang>.)
    assert_equal input, TavernKit::VibeTavern::OutputTags.transform(input, config: config)
  end

  test "strips control tag wrappers while preserving inner content" do
    config =
      build_config(
        enabled: true,
        rules: [{ tag: "lang", action: :strip }],
        sanitizers: {},
      )

    input = %(Hello <lang  code="ja">ありがとう</lang >.)
    assert_equal "Hello ありがとう.", TavernKit::VibeTavern::OutputTags.transform(input, config: config)
  end

  test "drops control tags entirely when configured" do
    config =
      build_config(
        enabled: true,
        rules: [{ tag: "think", action: :drop }],
        sanitizers: {},
      )

    input = %(A<think>secret</think>B)
    assert_equal "AB", TavernKit::VibeTavern::OutputTags.transform(input, config: config)
  end

  test "renames tags and remaps attributes when configured" do
    config =
      build_config(
        enabled: true,
        rules: [
          { tag: "lang", action: :rename, to: "span", attrs: { "code" => "data-lang" } },
        ],
        sanitizers: {},
      )

    input = %(<LANG CODE="ja-JP">ありがとう</LANG >)
    assert_equal %(<span data-lang="ja-JP">ありがとう</span>), TavernKit::VibeTavern::OutputTags.transform(input, config: config)
  end

  test "does not modify tags inside fenced code blocks or inline code" do
    config =
      build_config(
        enabled: true,
        rules: [{ tag: "lang", action: :strip }],
        sanitizers: {},
      )

    input = <<~TEXT
      Outside: <lang code="ja">ありがとう</lang>
      Inline: `<lang code="ja">NOPE</lang>`
      ```txt
      <lang code="ja">NOPE</lang>
      ```
    TEXT

    expected = <<~TEXT
      Outside: ありがとう
      Inline: `<lang code="ja">NOPE</lang>`
      ```txt
      <lang code="ja">NOPE</lang>
      ```
    TEXT

    assert_equal expected, TavernKit::VibeTavern::OutputTags.transform(input, config: config)
  end

  test "supports escaping tags with a backslash to avoid output tag processing" do
    config =
      build_config(
        enabled: true,
        rules: [{ tag: "lang", action: :strip }],
        sanitizers: { lang_spans: { enabled: true, validate_code: true, auto_close: true, on_invalid_code: :strip } },
        escape_hatch: { enabled: true, mode: :html_entity },
      )

    input = 'Hello \\<lang code="ja-jp">ありがとう\\</lang>.'
    expected = 'Hello &lt;lang code="ja-jp">ありがとう&lt;/lang>.'

    assert_equal expected, TavernKit::VibeTavern::OutputTags.transform(input, config: config)
  end

  test "escape hatch mode can be configured" do
    config =
      build_config(
        enabled: true,
        rules: [{ tag: "lang", action: :strip }],
        sanitizers: {},
        escape_hatch: { enabled: true, mode: :literal },
      )

    input = 'Hello \\<lang code="ja">ありがとう\\</lang>.'
    expected = "Hello <lang code=\"ja\">ありがとう</lang>."

    assert_equal expected, TavernKit::VibeTavern::OutputTags.transform(input, config: config)
  end

  test "escape hatch does not apply inside fenced code blocks" do
    config =
      build_config(
        enabled: true,
        rules: [{ tag: "lang", action: :strip }],
        sanitizers: {},
        escape_hatch: { enabled: true, mode: :html_entity },
      )

    input = <<~TEXT
      ```txt
      \\<lang code="ja">NOPE\\</lang>
      ```
    TEXT

    assert_equal input, TavernKit::VibeTavern::OutputTags.transform(input, config: config)
  end

  test "sanitizes messy <lang> tag forms and auto-closes missing spans when enabled" do
    config =
      build_config(
        enabled: true,
        rules: [],
        sanitizers: { lang_spans: { enabled: true, validate_code: true, auto_close: true, on_invalid_code: :strip } },
      )

    input = %(Outside: < lang  code="ja-jp" >ありがとう)
    expected = %(Outside: <lang code="ja-JP">ありがとう</lang>)
    assert_equal expected, TavernKit::VibeTavern::OutputTags.transform(input, config: config)
  end

  test "strips <lang> wrappers when code is not a valid BCP-47-ish tag" do
    config =
      build_config(
        enabled: true,
        rules: [],
        sanitizers: { lang_spans: { enabled: true, validate_code: true, auto_close: true, on_invalid_code: :strip } },
      )

    input = %(A<lang code="not a tag">X</lang>B)
    assert_equal "AXB", TavernKit::VibeTavern::OutputTags.transform(input, config: config)
  end

  test "lang span sanitizer respects verbatim zones" do
    config =
      build_config(
        enabled: true,
        rules: [],
        sanitizers: { lang_spans: { enabled: true, validate_code: true, auto_close: true, on_invalid_code: :strip } },
      )

    input = <<~TEXT
      ```txt
      < lang  code="ja" >NOPE
      ```
    TEXT

    assert_equal input, TavernKit::VibeTavern::OutputTags.transform(input, config: config)
  end

  test "handles nested control tags for strip rules" do
    config =
      build_config(
        enabled: true,
        rules: [{ tag: "lang", action: :strip }],
        sanitizers: {},
      )

    input = %(<lang code="ja">A<lang code="en">B</lang>C</lang>)
    assert_equal "ABC", TavernKit::VibeTavern::OutputTags.transform(input, config: config)
  end

  test "handles nested control tags for drop rules" do
    config =
      build_config(
        enabled: true,
        rules: [{ tag: "think", action: :drop }],
        sanitizers: {},
      )

    input = %(A<think>X<think>Y</think>Z</think>B)
    assert_equal "AB", TavernKit::VibeTavern::OutputTags.transform(input, config: config)
  end

  test "handles nested control tags for rename rules" do
    config =
      build_config(
        enabled: true,
        rules: [{ tag: "lang", action: :rename, to: "span" }],
        sanitizers: {},
      )

    input = %(<lang code="ja">A<lang code="en">B</lang>C</lang>)
    expected = %(<span code="ja">A<span code="en">B</span>C</span>)
    assert_equal expected, TavernKit::VibeTavern::OutputTags.transform(input, config: config)
  end
end
