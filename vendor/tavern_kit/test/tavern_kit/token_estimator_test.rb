# frozen_string_literal: true

require "test_helper"
require "tempfile"

class TavernKit::TokenEstimatorTest < Minitest::Test
  private

  def build_word_level_tokenizer_json
    require "tokenizers"

    vocab = { "[UNK]" => 0, "hello" => 1, "world" => 2, "😁" => 3 }
    model = Tokenizers::Models::WordLevel.new(vocab: vocab, unk_token: "[UNK]")
    tok = Tokenizers::Tokenizer.new(model)
    tok.pre_tokenizer = Tokenizers::PreTokenizers::Whitespace.new

    file = Tempfile.new(["tokenizer", ".json"])
    tok.save(file.path)
    file
  end

  public

  def test_estimate_uses_tiktoken
    estimator = TavernKit::TokenEstimator.default
    encoding = ::Tiktoken.get_encoding("cl100k_base")

    text = "hello world"
    assert_equal encoding.encode(text).length, estimator.estimate(text)
  end

  def test_describe_reports_backend_and_encoding
    estimator = TavernKit::TokenEstimator.default
    info = estimator.describe(model_hint: "gpt-4")

    assert_equal "tiktoken", info[:backend]
    assert_kind_of String, info[:encoding]
  end

  def test_unknown_model_hint_falls_back
    estimator = TavernKit::TokenEstimator.default
    assert_kind_of Integer, estimator.estimate("hello", model_hint: "unknown-model-xyz")
  end

  def test_registry_can_select_heuristic_backend
    estimator =
      TavernKit::TokenEstimator.new(
        registry: {
          "llama-3.1" => { tokenizer_family: :heuristic, chars_per_token: 2.0 },
        },
      )

    assert_equal 3, estimator.estimate("hello", model_hint: "llama-3.1") # ceil(5 / 2)
    info = estimator.describe(model_hint: "llama-3.1")
    assert_equal "heuristic", info[:backend]
    assert_equal true, info[:registry]
  end

  def test_tiktoken_adapter_caches_encoding_per_model_hint
    adapter = TavernKit::TokenEstimator::Adapter::Tiktoken.new

    calls = 0
    verbose, $VERBOSE = $VERBOSE, nil
    original = ::Tiktoken.method(:encoding_for_model)
    ::Tiktoken.define_singleton_method(:encoding_for_model) do |name|
      calls += 1
      original.call(name)
    end

    adapter.estimate("hello", model_hint: "gpt-4")
    adapter.estimate("world", model_hint: "gpt-4")

    assert_equal 1, calls
  ensure
    $VERBOSE = nil
    ::Tiktoken.define_singleton_method(:encoding_for_model, original) if original
    $VERBOSE = verbose
  end

  def test_estimate_never_raises_and_falls_back_to_heuristic
    raising_adapter =
      Class.new(TavernKit::TokenEstimator::Adapter::Base) do
        def estimate(_text, model_hint: nil)
          raise "boom"
        end
      end.new

    estimator = TavernKit::TokenEstimator.new(adapter: raising_adapter)

    assert_equal 2, estimator.estimate("hello", model_hint: "gpt-4") # ceil(5 / 4)
  end

  def test_registry_lookup_errors_are_tolerated
    registry =
      Class.new do
        def lookup(_key)
          raise "boom"
        end
      end.new

    estimator = TavernKit::TokenEstimator.new(registry: registry)

    assert_kind_of Integer, estimator.estimate("hello", model_hint: "any-model")
    assert_kind_of Hash, estimator.describe(model_hint: "any-model")
  end

  def test_registry_can_select_hf_tokenizers_backend
    tokenizer_json = build_word_level_tokenizer_json

    estimator =
      TavernKit::TokenEstimator.new(
        registry: {
          "oss-model" => { tokenizer_family: :hf_tokenizers, tokenizer_path: tokenizer_json.path },
        },
      )

    text = "hello 😁"
    assert_equal 2, estimator.estimate(text, model_hint: "oss-model")

    tokenization = estimator.tokenize(text, model_hint: "oss-model")
    assert_equal "hf_tokenizers", tokenization.backend
    assert_equal 2, tokenization.token_count
    assert_equal [1, 3], tokenization.ids
    assert_equal ["hello", "😁"], tokenization.tokens
    assert_equal [[0, 5], [6, 7]], tokenization.offsets
  ensure
    tokenizer_json&.close
    tokenizer_json&.unlink
  end

  def test_hf_backend_load_failure_falls_back_to_tiktoken
    estimator =
      TavernKit::TokenEstimator.new(
        registry: {
          "oss-model" => { tokenizer_family: :hf_tokenizers, tokenizer_path: "/nope/tokenizer.json" },
        },
      )

    text = "hello 😁"
    expected = ::Tiktoken.get_encoding("cl100k_base").encode(text).length
    assert_equal expected, estimator.estimate(text, model_hint: "oss-model")

    tokenization = estimator.tokenize(text, model_hint: "oss-model")
    assert_equal "tiktoken", tokenization.backend
    assert_equal expected, tokenization.token_count
    assert_kind_of Array, tokenization.ids
  end

  def test_hf_tokenizer_cache_loads_once_per_path
    tokenizer_json = build_word_level_tokenizer_json

    calls = 0
    verbose, $VERBOSE = $VERBOSE, nil
    original = Tokenizers.method(:from_file)
    Tokenizers.define_singleton_method(:from_file) do |path|
      calls += 1
      original.call(path)
    end

    estimator =
      TavernKit::TokenEstimator.new(
        registry: {
          "oss-model" => { tokenizer_family: :hf_tokenizers, tokenizer_path: tokenizer_json.path },
        },
      )

    2.times { estimator.estimate("hello 😁", model_hint: "oss-model") }
    assert_equal 1, calls
  ensure
    $VERBOSE = nil
    Tokenizers.define_singleton_method(:from_file, original) if original
    $VERBOSE = verbose
    tokenizer_json&.close
    tokenizer_json&.unlink
  end

  def test_preload_loads_hf_tokenizers_and_can_be_strict
    tokenizer_json = build_word_level_tokenizer_json

    estimator =
      TavernKit::TokenEstimator.new(
        registry: {
          "ok" => { tokenizer_family: :hf_tokenizers, tokenizer_path: tokenizer_json.path },
          "bad" => { tokenizer_family: :hf_tokenizers, tokenizer_path: "/nope/tokenizer.json" },
        },
      )

    result = estimator.preload!(strict: false)
    assert_equal [tokenizer_json.path], result.fetch(:loaded)
    assert_equal 1, result.fetch(:failed).size

    assert_raises(ArgumentError) do
      estimator.preload!(strict: true)
    end
  ensure
    tokenizer_json&.close
    tokenizer_json&.unlink
  end

  def test_hf_backend_missing_gem_falls_back_to_tiktoken
    verbose, $VERBOSE = $VERBOSE, nil
    Kernel.module_eval do
      alias_method :__tavernkit_token_estimator_orig_require, :require
      def require(name)
        raise LoadError, "cannot load such file -- tokenizers" if name == "tokenizers"

        __tavernkit_token_estimator_orig_require(name)
      end
    end

    estimator =
      TavernKit::TokenEstimator.new(
        registry: {
          "oss-model" => { tokenizer_family: :hf_tokenizers, tokenizer_path: "/any/tokenizer.json" },
        },
      )

    text = "hello 😁"
    expected = ::Tiktoken.get_encoding("cl100k_base").encode(text).length
    assert_equal expected, estimator.estimate(text, model_hint: "oss-model")

    tokenization = estimator.tokenize(text, model_hint: "oss-model")
    assert_equal "tiktoken", tokenization.backend
    assert_equal expected, tokenization.token_count
  ensure
    Kernel.module_eval do
      alias_method :require, :__tavernkit_token_estimator_orig_require
      remove_method :__tavernkit_token_estimator_orig_require
    end
    $VERBOSE = verbose
  end
end
