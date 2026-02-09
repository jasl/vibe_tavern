# frozen_string_literal: true

require "test_helper"

class TavernKit::TokenEstimatorTest < Minitest::Test
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
end
