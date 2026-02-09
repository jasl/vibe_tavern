require "test_helper"

class VibeTavernOutputTagsTest < ActiveSupport::TestCase
  setup do
    TavernKit::VibeTavern::Pipeline
  end

  test "does nothing when output tag processing is disabled" do
    runtime =
      TavernKit::Runtime::Base.build(
        { output_tags: { enabled: false } },
        type: :app,
      )

    input = %(Hello <lang code="ja">ありがとう</lang>.)
    assert_equal input, TavernKit::VibeTavern::OutputTags.transform(input, runtime: runtime)
  end

  test "strips control tag wrappers while preserving inner content" do
    runtime =
      TavernKit::Runtime::Base.build(
        {
          output_tags: {
            enabled: true,
            rules: [{ tag: "lang", action: :strip }],
            sanitizers: {},
          },
        },
        type: :app,
      )

    input = %(Hello <lang  code="ja">ありがとう</lang >.)
    assert_equal "Hello ありがとう.", TavernKit::VibeTavern::OutputTags.transform(input, runtime: runtime)
  end

  test "drops control tags entirely when configured" do
    runtime =
      TavernKit::Runtime::Base.build(
        {
          output_tags: {
            enabled: true,
            rules: [{ tag: "think", action: :drop }],
            sanitizers: {},
          },
        },
        type: :app,
      )

    input = %(A<think>secret</think>B)
    assert_equal "AB", TavernKit::VibeTavern::OutputTags.transform(input, runtime: runtime)
  end

  test "renames tags and remaps attributes when configured" do
    runtime =
      TavernKit::Runtime::Base.build(
        {
          output_tags: {
            enabled: true,
            rules: [
              { tag: "lang", action: :rename, to: "span", attrs: { "code" => "data-lang" } },
            ],
            sanitizers: {},
          },
        },
        type: :app,
      )

    input = %(<LANG CODE="ja-JP">ありがとう</LANG >)
    assert_equal %(<span data-lang="ja-JP">ありがとう</span>), TavernKit::VibeTavern::OutputTags.transform(input, runtime: runtime)
  end

  test "does not modify tags inside fenced code blocks or inline code" do
    runtime =
      TavernKit::Runtime::Base.build(
        {
          output_tags: {
            enabled: true,
            rules: [{ tag: "lang", action: :strip }],
            sanitizers: {},
          },
        },
        type: :app,
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

    assert_equal expected, TavernKit::VibeTavern::OutputTags.transform(input, runtime: runtime)
  end

  test "supports escaping tags with a backslash to avoid output tag processing" do
    runtime =
      TavernKit::Runtime::Base.build(
        {
          output_tags: {
            enabled: true,
            rules: [{ tag: "lang", action: :strip }],
            sanitizers: { lang_spans: { enabled: true, validate_code: true, auto_close: true, on_invalid_code: :strip } },
            escape_hatch: { enabled: true, mode: :html_entity },
          },
        },
        type: :app,
      )

    input = 'Hello \\<lang code="ja-jp">ありがとう\\</lang>.'
    expected = 'Hello &lt;lang code="ja-jp">ありがとう&lt;/lang>.'

    assert_equal expected, TavernKit::VibeTavern::OutputTags.transform(input, runtime: runtime)
  end

  test "escape hatch mode can be configured" do
    runtime =
      TavernKit::Runtime::Base.build(
        {
          output_tags: {
            enabled: true,
            rules: [{ tag: "lang", action: :strip }],
            sanitizers: {},
            escape_hatch: { enabled: true, mode: :literal },
          },
        },
        type: :app,
      )

    input = 'Hello \\<lang code="ja">ありがとう\\</lang>.'
    expected = 'Hello <lang code="ja">ありがとう</lang>.'

    assert_equal expected, TavernKit::VibeTavern::OutputTags.transform(input, runtime: runtime)
  end

  test "escape hatch does not apply inside fenced code blocks" do
    runtime =
      TavernKit::Runtime::Base.build(
        {
          output_tags: {
            enabled: true,
            rules: [{ tag: "lang", action: :strip }],
            sanitizers: {},
            escape_hatch: { enabled: true, mode: :html_entity },
          },
        },
        type: :app,
      )

    input = <<~TEXT
      ```txt
      \\<lang code="ja">NOPE\\</lang>
      ```
    TEXT

    assert_equal input, TavernKit::VibeTavern::OutputTags.transform(input, runtime: runtime)
  end

  test "sanitizes messy <lang> tag forms and auto-closes missing spans when enabled" do
    runtime =
      TavernKit::Runtime::Base.build(
        {
          output_tags: {
            enabled: true,
            rules: [],
            sanitizers: { lang_spans: { enabled: true, validate_code: true, auto_close: true, on_invalid_code: :strip } },
          },
        },
        type: :app,
      )

    input = %(Outside: < lang  code="ja-jp" >ありがとう)
    expected = %(Outside: <lang code="ja-JP">ありがとう</lang>)
    assert_equal expected, TavernKit::VibeTavern::OutputTags.transform(input, runtime: runtime)
  end

  test "strips <lang> wrappers when code is not a valid BCP-47-ish tag" do
    runtime =
      TavernKit::Runtime::Base.build(
        {
          output_tags: {
            enabled: true,
            rules: [],
            sanitizers: { lang_spans: { enabled: true, validate_code: true, auto_close: true, on_invalid_code: :strip } },
          },
        },
        type: :app,
      )

    input = %(A<lang code="not a tag">X</lang>B)
    assert_equal "AXB", TavernKit::VibeTavern::OutputTags.transform(input, runtime: runtime)
  end

  test "lang span sanitizer respects verbatim zones" do
    runtime =
      TavernKit::Runtime::Base.build(
        {
          output_tags: {
            enabled: true,
            rules: [],
            sanitizers: { lang_spans: { enabled: true, validate_code: true, auto_close: true, on_invalid_code: :strip } },
          },
        },
        type: :app,
      )

    input = <<~TEXT
      ```txt
      < lang  code="ja" >NOPE
      ```
    TEXT

    assert_equal input, TavernKit::VibeTavern::OutputTags.transform(input, runtime: runtime)
  end
end
