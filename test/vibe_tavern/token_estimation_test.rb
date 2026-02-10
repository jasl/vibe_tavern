# frozen_string_literal: true

require "test_helper"
require "pathname"

class VibeTavernTokenEstimationTest < ActiveSupport::TestCase
  def with_credentials_tokenizer_root(value)
    mod = TavernKit::VibeTavern::TokenEstimation
    original = mod.method(:credentials_tokenizer_root)
    mod.define_singleton_method(:credentials_tokenizer_root) { value }
    yield
  ensure
    mod.define_singleton_method(:credentials_tokenizer_root, original)
  end

  test "canonical_model_hint normalizes common variants" do
    assert_equal "deepseek-v3", TavernKit::VibeTavern::TokenEstimation.canonical_model_hint("deepseek/deepseek-chat-v3-0324:nitro")
    assert_equal "deepseek-v3", TavernKit::VibeTavern::TokenEstimation.canonical_model_hint("deepseek-ai/DeepSeek-V3-0324")
    assert_equal "deepseek-v3.2", TavernKit::VibeTavern::TokenEstimation.canonical_model_hint("deepseek/deepseek-v3.2:nitro")

    assert_equal(
      "qwen3-30b-a3b-instruct",
      TavernKit::VibeTavern::TokenEstimation.canonical_model_hint("qwen/qwen3-30b-a3b-instruct-2507:nitro"),
    )

    assert_equal "gpt-5.2", TavernKit::VibeTavern::TokenEstimation.canonical_model_hint("openai/gpt-5.2:nitro")
    assert_equal "kimi-k2.5", TavernKit::VibeTavern::TokenEstimation.canonical_model_hint("moonshotai/kimi-k2.5:nitro")
    assert_equal "minimax-m2.1", TavernKit::VibeTavern::TokenEstimation.canonical_model_hint("minimax/minimax-m2-her")

    assert_equal "google/gemini-2.5-flash", TavernKit::VibeTavern::TokenEstimation.canonical_model_hint("google/gemini-2.5-flash:nitro")
  end

  test "registry exposes hf_tokenizers paths under vendor/tokenizers" do
    root = Pathname.new("/example/root")
    registry = TavernKit::VibeTavern::TokenEstimation.registry(root: root)

    assert_equal(
      {
        tokenizer_family: :hf_tokenizers,
        tokenizer_path: "/example/root/vendor/tokenizers/deepseek-v3/tokenizer.json",
        source_hint: "deepseek-v3",
        source_repo: "deepseek-ai/DeepSeek-V3-0324",
      },
      registry.fetch("deepseek-v3"),
    )

    assert_equal(
      {
        tokenizer_family: :hf_tokenizers,
        tokenizer_path: "/example/root/vendor/tokenizers/qwen3/tokenizer.json",
        source_hint: "qwen3",
        source_repo: "Qwen/Qwen3-30B-A3B-Instruct-2507",
      },
      registry.fetch("qwen3"),
    )

    assert_equal(
      {
        tokenizer_family: :tiktoken,
        source_hint: "kimi-k2.5",
      },
      registry.fetch("kimi-k2.5"),
    )
  end

  test "Prepare injects canonical model_hint and default estimator" do
    ctx = TavernKit::PromptBuilder::State.new
    ctx[:default_model_hint] = "deepseek/deepseek-chat-v3-0324:nitro"

    pipeline =
      TavernKit::PromptBuilder::Pipeline.new do
        use_step TavernKit::VibeTavern::PromptBuilder::Steps::Prepare, name: :prepare
      end

    pipeline.call(ctx)

    assert_equal "deepseek-v3", ctx[:model_hint]
    assert_same TavernKit::VibeTavern::TokenEstimation.estimator, ctx.token_estimator

    count = ctx.token_estimator.estimate("hello 😁", model_hint: ctx[:model_hint])
    assert_kind_of Integer, count
    assert_operator count, :>=, 1
  end

  test "tokenizer_path uses tokenizer_root from creds when present" do
    with_credentials_tokenizer_root("shared/tokenizers") do
      assert_equal(
        "/example/root/shared/tokenizers/deepseek-v3/tokenizer.json",
        TavernKit::VibeTavern::TokenEstimation.tokenizer_path(root: "/example/root", hint: "deepseek-v3"),
      )
    end

    with_credentials_tokenizer_root("/opt/tokenizers") do
      assert_equal(
        "/opt/tokenizers/qwen3/tokenizer.json",
        TavernKit::VibeTavern::TokenEstimation.tokenizer_path(root: "/example/root", hint: "qwen3"),
      )
    end
  end
end
