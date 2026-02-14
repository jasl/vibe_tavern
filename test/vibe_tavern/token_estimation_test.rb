# frozen_string_literal: true

require "test_helper"
require "pathname"

class VibeTavernTokenEstimationTest < ActiveSupport::TestCase
  def with_token_estimation_config(root: nil, tokenizer_root: nil)
    mod = AgentCore::Contrib::TokenEstimation
    original = mod.config
    mod.configure(root: root, tokenizer_root: tokenizer_root)
    yield
  ensure
    mod.configure(root: original.root, tokenizer_root: original.tokenizer_root)
  end

  def with_env(key, value)
    key = key.to_s
    original_missing = !ENV.key?(key)
    original = ENV[key]

    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end

    yield
  ensure
    if original_missing
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end

  test "canonical_model_hint normalizes common variants" do
    assert_equal "deepseek-v3", AgentCore::Contrib::TokenEstimation.canonical_model_hint("deepseek/deepseek-chat-v3-0324:nitro")
    assert_equal "deepseek-v3", AgentCore::Contrib::TokenEstimation.canonical_model_hint("deepseek-ai/DeepSeek-V3-0324")
    assert_equal "deepseek-v3.2", AgentCore::Contrib::TokenEstimation.canonical_model_hint("deepseek/deepseek-v3.2:nitro")

    assert_equal(
      "qwen3-30b-a3b-instruct",
      AgentCore::Contrib::TokenEstimation.canonical_model_hint("qwen/qwen3-30b-a3b-instruct-2507:nitro"),
    )

    assert_equal "gpt-5.2", AgentCore::Contrib::TokenEstimation.canonical_model_hint("openai/gpt-5.2:nitro")
    assert_equal "kimi-k2.5", AgentCore::Contrib::TokenEstimation.canonical_model_hint("moonshotai/kimi-k2.5:nitro")
    assert_equal "minimax-m2.1", AgentCore::Contrib::TokenEstimation.canonical_model_hint("minimax/minimax-m2-her")
    assert_equal "minimax-m2.5", AgentCore::Contrib::TokenEstimation.canonical_model_hint("minimax/minimax-m2.5:nitro")
    assert_equal "glm-5", AgentCore::Contrib::TokenEstimation.canonical_model_hint("z-ai/glm-5:nitro")

    assert_equal "google/gemini-2.5-flash", AgentCore::Contrib::TokenEstimation.canonical_model_hint("google/gemini-2.5-flash:nitro")
  end

  test "registry exposes hf_tokenizers paths under vendor/tokenizers" do
    mod = AgentCore::Contrib::TokenEstimation

    with_env(mod::TOKENIZER_ROOT_ENV_KEY, nil) do
      with_token_estimation_config(root: nil, tokenizer_root: nil) do
        root = Pathname.new("/example/root")
        registry = mod.registry(root: root)

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

        assert_equal(
          {
            tokenizer_family: :hf_tokenizers,
            tokenizer_path: "/example/root/vendor/tokenizers/glm-5/tokenizer.json",
            source_hint: "glm-5",
            source_repo: "zai-org/GLM-5",
          },
          registry.fetch("glm-5"),
        )

        assert_equal(
          {
            tokenizer_family: :hf_tokenizers,
            tokenizer_path: "/example/root/vendor/tokenizers/minimax-m2.5/tokenizer.json",
            source_hint: "minimax-m2.5",
            source_repo: "MiniMaxAI/MiniMax-M2.5",
          },
          registry.fetch("minimax-m2.5"),
        )
      end
    end
  end

  test "estimator is usable with canonical model_hint" do
    mod = AgentCore::Contrib::TokenEstimation

    with_env(mod::ROOT_ENV_KEY, nil) do
      with_token_estimation_config(root: "/example/root", tokenizer_root: nil) do
        estimator = mod.estimator
        model_hint = mod.canonical_model_hint("deepseek/deepseek-chat-v3-0324:nitro")

        count = estimator.estimate("hello 😁", model_hint: model_hint)
        assert_kind_of AgentCore::Contrib::TokenEstimator, estimator
        assert_equal "deepseek-v3", model_hint
        assert_kind_of Integer, count
        assert_operator count, :>=, 1
      end
    end
  end

  test "default_root uses configured root when present" do
    mod = AgentCore::Contrib::TokenEstimation

    with_env(mod::ROOT_ENV_KEY, nil) do
      with_token_estimation_config(root: "/example/root", tokenizer_root: nil) do
        assert_equal "/example/root", mod.default_root.to_s
      end
    end
  end

  test "default_root uses VIBE_TAVERN_ROOT when config.root is blank" do
    mod = AgentCore::Contrib::TokenEstimation

    with_token_estimation_config(root: nil, tokenizer_root: nil) do
      with_env(mod::ROOT_ENV_KEY, "/env/root") do
        assert_equal "/env/root", mod.default_root.to_s
      end
    end
  end

  test "default_root raises when neither config nor ENV provide root" do
    mod = AgentCore::Contrib::TokenEstimation

    with_token_estimation_config(root: nil, tokenizer_root: nil) do
      with_env(mod::ROOT_ENV_KEY, nil) do
        assert_raises(mod::ConfigurationError) { mod.default_root }
      end
    end
  end

  test "tokenizer_path uses configured tokenizer_root when present" do
    mod = AgentCore::Contrib::TokenEstimation

    with_env(mod::TOKENIZER_ROOT_ENV_KEY, nil) do
      with_token_estimation_config(root: nil, tokenizer_root: "shared/tokenizers") do
        assert_equal(
          "/example/root/shared/tokenizers/deepseek-v3/tokenizer.json",
          mod.tokenizer_path(root: "/example/root", hint: "deepseek-v3"),
        )
      end

      with_token_estimation_config(root: nil, tokenizer_root: "/opt/tokenizers") do
        assert_equal(
          "/opt/tokenizers/qwen3/tokenizer.json",
          mod.tokenizer_path(root: "/example/root", hint: "qwen3"),
        )
      end
    end
  end

  test "tokenizer_path uses TOKEN_ESTIMATION__TOKENIZER_ROOT when config.tokenizer_root is blank" do
    mod = AgentCore::Contrib::TokenEstimation

    with_token_estimation_config(root: nil, tokenizer_root: nil) do
      with_env(mod::TOKENIZER_ROOT_ENV_KEY, "shared/tokenizers") do
        assert_equal(
          "/example/root/shared/tokenizers/deepseek-v3/tokenizer.json",
          mod.tokenizer_path(root: "/example/root", hint: "deepseek-v3"),
        )
      end
    end
  end
end
