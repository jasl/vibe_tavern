# frozen_string_literal: true

require "test_helper"

class TavernKit::LoadHooksTest < Minitest::Test
  def setup
    super
    TavernKit::LoadHooks.reset!
  end

  def test_on_load_then_run_load_hooks_executes_hook
    calls = []

    TavernKit.on_load(:spec) { |payload| calls << payload }
    assert_equal [], calls

    TavernKit.run_load_hooks(:spec, :ok)
    assert_equal [:ok], calls
  end

  def test_run_load_hooks_then_on_load_executes_immediately
    calls = []

    TavernKit.run_load_hooks(:spec, "payload")
    TavernKit.on_load(:spec) { |payload| calls << payload }

    assert_equal ["payload"], calls
  end

  def test_id_dedup_overrides_previous_hook
    calls = []

    TavernKit.run_load_hooks(:spec, "p1")

    TavernKit.on_load(:spec, id: :once) { |payload| calls << "v1:#{payload}" }
    TavernKit.on_load(:spec, id: :once) { |payload| calls << "v2:#{payload}" }

    assert_equal ["v1:p1", "v2:p1"], calls

    calls.clear
    TavernKit.run_load_hooks(:spec, "p2")
    assert_equal ["v2:p2"], calls
  end

  def test_run_load_hooks_replaces_payload_and_replays_hooks
    calls = []

    TavernKit.on_load(:spec) { |payload| calls << payload }
    TavernKit.run_load_hooks(:spec, 1)
    TavernKit.run_load_hooks(:spec, 2)

    assert_equal [1, 2], calls
  end
end

