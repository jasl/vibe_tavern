# frozen_string_literal: true

require "test_helper"

class AgentCore::Observability::TraceRecorderTest < Minitest::Test
  def test_instrument_records_duration_and_returns_value
    recorder = AgentCore::Observability::TraceRecorder.new(capture: :none)

    value = recorder.instrument("test.op", foo: "bar") { 123 }

    assert_equal 123, value
    assert_equal 1, recorder.trace.size

    event = recorder.trace.first
    assert_equal "test.op", event.fetch(:name)
    payload = event.fetch(:payload)
    assert payload.key?(:duration_ms)
    assert payload.fetch(:duration_ms) >= 0
  end
  def test_instrument_records_error_and_reraises
    recorder = AgentCore::Observability::TraceRecorder.new(capture: :none)

    err = assert_raises(RuntimeError) do
      recorder.instrument("test.op") { raise "boom" }
    end
    assert_equal "boom", err.message

    event = recorder.trace.first
    payload = event.fetch(:payload)
    assert_equal({ class: "RuntimeError", message: "boom" }, payload.fetch(:error))
  end

  def test_capture_levels
    recorder_none = AgentCore::Observability::TraceRecorder.new(capture: :none)
    recorder_safe = AgentCore::Observability::TraceRecorder.new(capture: :safe)
    recorder_full = AgentCore::Observability::TraceRecorder.new(capture: :full)

    payload = { content: "secret", ok: true }

    recorder_none.instrument("op", payload) { }
    recorder_safe.instrument("op", payload) { }
    recorder_full.instrument("op", payload) { }

    none_payload = recorder_none.trace.first.fetch(:payload)
    safe_payload = recorder_safe.trace.first.fetch(:payload)
    full_payload = recorder_full.trace.first.fetch(:payload)

    refute_includes none_payload.keys, "content"
    assert_equal "[redacted]", safe_payload.fetch("content")
    assert_equal "secret", full_payload.fetch("content")
  end

  def test_truncation
    recorder = AgentCore::Observability::TraceRecorder.new(capture: :full, max_string_bytes: 8)
    recorder.instrument("op", value: "1234567890") { }

    payload = recorder.trace.first.fetch(:payload)
    assert payload.fetch("value").end_with?("...[truncated]")
  end

  def test_custom_redactor
    redactor =
      lambda do |_name, payload|
        payload.merge("ok" => "X")
      end

    recorder = AgentCore::Observability::TraceRecorder.new(capture: :full, redactor: redactor)
    recorder.instrument("op", ok: "yes") { }

    payload = recorder.trace.first.fetch(:payload)
    assert_equal "X", payload.fetch("ok")
  end
end
