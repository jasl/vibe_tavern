# frozen_string_literal: true

require "test_helper"
require "pathname"

class VibeTavernTokenEstimationTest < ActiveSupport::TestCase
  test "canonical_model_hint normalizes common variants" do
    assert_equal "deepseek", TavernKit::VibeTavern::TokenEstimation.canonical_model_hint("deepseek/deepseek-chat-v3-0324:nitro")
    assert_equal "deepseek", TavernKit::VibeTavern::TokenEstimation.canonical_model_hint("deepseek-ai/DeepSeek-V3-0324")

    assert_equal "qwen3", TavernKit::VibeTavern::TokenEstimation.canonical_model_hint("qwen/qwen3-30b-a3b-instruct-2507:nitro")

    assert_equal "gpt-5.2", TavernKit::VibeTavern::TokenEstimation.canonical_model_hint("openai/gpt-5.2:nitro")

    assert_equal "google/gemini-2.5-flash", TavernKit::VibeTavern::TokenEstimation.canonical_model_hint("google/gemini-2.5-flash:nitro")
  end

  test "registry exposes hf_tokenizers paths under vendor/tokenizers" do
    root = Pathname.new("/example/root")
    registry = TavernKit::VibeTavern::TokenEstimation.registry(root: root)

    assert_equal(
      {
        tokenizer_family: :hf_tokenizers,
        tokenizer_path: "/example/root/vendor/tokenizers/deepseek/tokenizer.json",
      },
      registry.fetch("deepseek"),
    )

    assert_equal(
      {
        tokenizer_family: :hf_tokenizers,
        tokenizer_path: "/example/root/vendor/tokenizers/qwen3/tokenizer.json",
      },
      registry.fetch("qwen3"),
    )
  end

  test "Prepare injects canonical model_hint and default estimator" do
    ctx = TavernKit::Prompt::Context.new
    ctx[:default_model_hint] = "deepseek/deepseek-chat-v3-0324:nitro"

    pipeline =
      TavernKit::Prompt::Pipeline.new do
        use TavernKit::VibeTavern::Middleware::Prepare, name: :prepare
      end

    pipeline.call(ctx)

    assert_equal "deepseek", ctx[:model_hint]
    assert_same TavernKit::VibeTavern::TokenEstimation.estimator, ctx.token_estimator

    count = ctx.token_estimator.estimate("hello 😁", model_hint: ctx[:model_hint])
    assert_kind_of Integer, count
    assert_operator count, :>=, 1
  end
end
