# frozen_string_literal: true

require "test_helper"

class AgentCoreContribLanguagePolicyPromptTest < ActiveSupport::TestCase
  test "build requires target_lang" do
    assert_raises(ArgumentError) { AgentCore::Contrib::LanguagePolicyPrompt.build("") }
  end

  test "build includes tool-calls rule by default but can be disabled" do
    prompt = AgentCore::Contrib::LanguagePolicyPrompt.build("zh-CN")
    assert_includes prompt, "Tool calls:"

    prompt2 = AgentCore::Contrib::LanguagePolicyPrompt.build("zh-CN", tool_calls_rule: false)
    refute_includes prompt2, "Tool calls:"
  end

  test "build supports style_hint and special tags" do
    prompt =
      AgentCore::Contrib::LanguagePolicyPrompt.build(
        "zh-CN",
        style_hint: "concise",
        special_tags: ["lang", "draft"],
      )

    assert_includes prompt, "Style: concise."
    assert_includes prompt, "Special tags:"
    assert_includes prompt, "<lang code="
  end
end
