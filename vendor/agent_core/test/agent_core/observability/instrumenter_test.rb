# frozen_string_literal: true

require "test_helper"

module AgentCore
  module Observability
    class InstrumenterTest < Minitest::Test
      class ExplodingInstrumenter < Instrumenter
        def _publish(_name, _payload)
          raise "publish failed"
        end
      end

      def test_publish_never_raises
        inst = ExplodingInstrumenter.new
        inst.publish("agent_core.test", { ok: true })
      end

      def test_instrument_does_not_fail_when_publish_fails
        inst = ExplodingInstrumenter.new

        payload = { ok: true }
        result = inst.instrument("agent_core.test", payload) { 123 }

        assert_equal 123, result
        assert payload[:duration_ms].is_a?(Numeric)
      end

      def test_instrument_does_not_mask_original_error_when_publish_fails
        inst = ExplodingInstrumenter.new

        err = assert_raises(RuntimeError) do
          inst.instrument("agent_core.test") { raise "work failed" }
        end

        assert_equal "work failed", err.message
      end
    end
  end
end
