# frozen_string_literal: true

require "test_helper"

class TestSimpleInference < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::SimpleInference::VERSION
  end

  def test_simple_inference_is_loaded
    refute_nil ::SimpleInference::Client
  end
end
