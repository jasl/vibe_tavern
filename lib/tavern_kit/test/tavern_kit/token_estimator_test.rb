# frozen_string_literal: true

require "test_helper"

class TavernKit::TokenEstimatorTest < Minitest::Test
  def test_estimate_uses_tiktoken
    estimator = TavernKit::TokenEstimator.default
    encoding = ::Tiktoken.get_encoding("cl100k_base")

    text = "hello world"
    assert_equal encoding.encode(text).length, estimator.estimate(text)
  end

  def test_unknown_model_hint_falls_back
    estimator = TavernKit::TokenEstimator.default
    assert_kind_of Integer, estimator.estimate("hello", model_hint: "unknown-model-xyz")
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
end
