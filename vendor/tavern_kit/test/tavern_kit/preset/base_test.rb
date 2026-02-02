# frozen_string_literal: true

require "test_helper"

class TavernKit::Preset::BaseTest < Minitest::Test
  class FakePreset < TavernKit::Preset::Base
    def initialize(context_window_tokens:, reserved_response_tokens:)
      @context_window_tokens = context_window_tokens
      @reserved_response_tokens = reserved_response_tokens
    end

    def context_window_tokens = @context_window_tokens
    def reserved_response_tokens = @reserved_response_tokens
  end

  def test_max_prompt_tokens
    preset = FakePreset.new(context_window_tokens: 8192, reserved_response_tokens: 512)
    assert_equal 7680, preset.max_prompt_tokens
  end
end
