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
end
