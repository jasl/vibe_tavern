require "test_helper"

require Rails.root.join("db/seeds/llm").to_s

class LLMSeedsTest < ActiveSupport::TestCase
  test "seeds providers, OpenRouter models, and default presets (idempotent)" do
    DbSeeds::LLM.call

    openrouter = LLMProvider.find_by!(name: "OpenRouter")
    assert_equal "openai", openrouter.api_format

    models = LLMModel.where(llm_provider: openrouter).order(:model)
    assert_equal 17, models.count
    assert_equal 17, models.enabled.count

    models.each do |m|
      assert_equal true, m.enabled
      assert_equal 1, m.llm_presets.where(key: "default").count
    end

    claude = models.find { |m| m.model.start_with?("anthropic/") }
    assert_equal false, claude.supports_response_format_json_schema

    gpt = models.find { |m| m.model.start_with?("openai/") }
    assert_equal false, gpt.supports_response_format_json_object
    assert_equal false, gpt.supports_response_format_json_schema

    m2_her = models.find { |m| m.model == "minimax/minimax-m2-her" }
    assert_equal false, m2_her.supports_tool_calling

    deepseek_v3_2 = models.find { |m| m.model == "deepseek/deepseek-v3.2:nitro" }
    ds_default = deepseek_v3_2.llm_presets.find_by!(key: "default")
    assert_equal({ "temperature" => 1.0, "top_p" => 0.95 }, ds_default.llm_options_overrides)

    gemini = models.find { |m| m.model == "google/gemini-2.5-flash:nitro" }
    gemini_default = gemini.llm_presets.find_by!(key: "default")
    assert_equal({}, gemini_default.llm_options_overrides)

    # Seeds should not overwrite user edits on re-run.
    openrouter.update!(base_url: "http://changed.test")
    gemini.update!(enabled: false)
    ds_default.update!(llm_options_overrides: { temperature: 0.123 })

    DbSeeds::LLM.call

    assert_equal "http://changed.test", openrouter.reload.base_url
    assert_equal false, gemini.reload.enabled
    assert_equal({ "temperature" => 0.123 }, ds_default.reload.llm_options_overrides)
  end
end
