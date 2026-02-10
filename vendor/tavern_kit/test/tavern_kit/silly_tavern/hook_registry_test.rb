# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::HookRegistryTest < Minitest::Test
  def test_runs_hooks_in_registration_order
    registry = TavernKit::SillyTavern::HookRegistry.new
    calls = []

    registry.before_build do |ctx|
      calls << :before_1
      ctx[:count] = 1
    end

    registry.before_build do |ctx|
      calls << :before_2
      ctx[:count] += 1
    end

    registry.after_build do |_ctx|
      calls << :after_1
    end

    ctx = TavernKit::PromptBuilder::Context.new
    registry.run_before_build(ctx)
    registry.run_after_build(ctx)

    assert_equal 2, ctx[:count]
    assert_equal %i[before_1 before_2 after_1], calls
  end
end
