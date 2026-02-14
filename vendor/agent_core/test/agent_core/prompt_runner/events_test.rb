# frozen_string_literal: true

require "test_helper"

class AgentCore::PromptRunner::EventsTest < Minitest::Test
  def setup
    @events = AgentCore::PromptRunner::Events.new
  end

  def test_hooks_constant
    assert_includes AgentCore::PromptRunner::Events::HOOKS, :turn_start
    assert_includes AgentCore::PromptRunner::Events::HOOKS, :tool_call
    assert_includes AgentCore::PromptRunner::Events::HOOKS, :error
    assert AgentCore::PromptRunner::Events::HOOKS.frozen?
  end

  def test_on_turn_start_registers_callback
    called = false
    @events.on_turn_start { called = true }
    @events.emit(:turn_start)
    assert called
  end

  def test_on_method_returns_self
    result = @events.on_turn_start { nil }
    assert_same @events, result
  end

  def test_generic_on_registers_callback
    called_with = nil
    @events.on(:tool_call) { |name| called_with = name }
    @events.emit(:tool_call, "read_file")
    assert_equal "read_file", called_with
  end

  def test_generic_on_rejects_unknown_hook
    assert_raises(ArgumentError) { @events.on(:nonexistent) { nil } }
  end

  def test_generic_on_returns_self
    result = @events.on(:error) { nil }
    assert_same @events, result
  end

  def test_emit_multiple_callbacks
    calls = []
    @events.on_turn_start { calls << :a }
    @events.on_turn_start { calls << :b }
    @events.emit(:turn_start)
    assert_equal %i[a b], calls
  end

  def test_emit_passes_multiple_args
    captured = nil
    @events.on(:tool_result) { |*args| captured = args }
    @events.emit(:tool_result, "name", "result", "id")
    assert_equal ["name", "result", "id"], captured
  end

  def test_callback_error_does_not_stop_others
    calls = []
    @events.on_turn_start { raise "boom" }
    @events.on_turn_start { calls << :after_error }
    @events.emit(:turn_start)
    assert_equal [:after_error], calls
  end

  def test_callback_error_triggers_error_hook
    errors = []
    @events.on(:error) { |e, _| errors << e.message }
    @events.on_turn_start { raise "callback error" }
    @events.emit(:turn_start)
    assert_equal ["callback error"], errors
  end

  def test_error_hook_failure_does_not_recurse
    # When emitting :error directly, callback failures are swallowed (next if hook == :error)
    @events.on(:error) { raise "error in error handler" }
    # Emitting :error directly should not raise or hang
    @events.emit(:error, RuntimeError.new("original"), false)
  end

  def test_error_callback_failure_propagates_from_non_error_hook
    # When a non-error hook callback fails and the error handler also fails,
    # the error handler's exception propagates (it's not rescued).
    @events.on(:error) { raise "error in error handler" }
    @events.on_turn_start { raise "boom" }
    assert_raises(RuntimeError) { @events.emit(:turn_start) }
  end

  def test_has_listeners_true
    @events.on_turn_start { nil }
    assert @events.has_listeners?(:turn_start)
  end

  def test_has_listeners_false
    refute @events.has_listeners?(:turn_start)
  end

  def test_has_listeners_unknown_hook
    refute @events.has_listeners?(:nonexistent)
  end
end
