# frozen_string_literal: true

require "test_helper"

module AgentCore
  module Observability
    class AdaptersTest < Minitest::Test
      class FakeNotifications
        attr_reader :events

        def initialize
          @events = []
        end

        def instrument(name, payload)
          result = nil
          begin
            result = yield if block_given?
          ensure
            @events << { name: name.to_s, payload: payload.dup }.freeze
          end
          result
        end
      end

      class ExplodingNotificationsBeforeYield < FakeNotifications
        def instrument(_name, _payload)
          raise "notifier boom"
        end
      end

      class ExplodingNotificationsAfterYield < FakeNotifications
        def instrument(name, payload)
          super
          raise "notifier boom"
        end
      end

      class ExplodingNotificationsInEnsure < FakeNotifications
        def instrument(name, payload)
          super
        ensure
          raise "notifier boom"
        end
      end

      class FakeSpan
        attr_reader :attributes, :exceptions

        def initialize
          @attributes = {}
          @exceptions = []
        end

        def set_attribute(key, value)
          @attributes[key] = value
        end

        def record_exception(error)
          @exceptions << error
        end
      end

      class ExplodingSpan < FakeSpan
        def set_attribute(key, value)
          super
          raise "set_attribute boom"
        end
      end

      class FakeTracer
        attr_reader :spans

        def initialize
          @spans = []
        end

        def in_span(name, attributes: {})
          span = FakeSpan.new
          @spans << { name: name.to_s, attributes: attributes.dup, span: span }.freeze
          yield span
        end
      end

      class ExplodingTracerBeforeYield < FakeTracer
        def in_span(_name, attributes: {})
          raise "tracer boom"
        end
      end

      class ExplodingTracerAfterYield < FakeTracer
        def in_span(name, attributes: {})
          super
          raise "tracer boom"
        end
      end

      class TracerWithExplodingSpan < FakeTracer
        def in_span(name, attributes: {})
          span = ExplodingSpan.new
          @spans << { name: name.to_s, attributes: attributes.dup, span: span }.freeze
          yield span
        end
      end

      def test_active_support_notifications_instrumenter_instruments_and_publishes
        require "agent_core/observability/adapters/active_support_notifications_instrumenter"

        notifier = FakeNotifications.new
        inst = Adapters::ActiveSupportNotificationsInstrumenter.new(notifier: notifier)

        payload = { run_id: "r1" }
        result = inst.instrument("agent_core.test", payload) { 123 }

        assert_equal 123, result
        assert payload[:duration_ms].is_a?(Numeric)
        assert_operator payload[:duration_ms], :>=, 0
        assert_nil payload[:error]

        assert_equal 1, notifier.events.size
        assert_equal "agent_core.test", notifier.events.first.fetch(:name)
        assert_equal "r1", notifier.events.first.fetch(:payload).fetch(:run_id)
        assert notifier.events.first.fetch(:payload).key?(:duration_ms)
      end

      def test_active_support_notifications_instrumenter_falls_back_when_notifier_raises_before_yield
        require "agent_core/observability/adapters/active_support_notifications_instrumenter"

        notifier = ExplodingNotificationsBeforeYield.new
        inst = Adapters::ActiveSupportNotificationsInstrumenter.new(notifier: notifier)

        calls = 0
        result =
          inst.instrument("agent_core.test", {}) do
            calls += 1
            "ok"
          end

        assert_equal "ok", result
        assert_equal 1, calls
      end

      def test_active_support_notifications_instrumenter_does_not_double_yield_when_notifier_raises_after_block
        require "agent_core/observability/adapters/active_support_notifications_instrumenter"

        notifier = ExplodingNotificationsAfterYield.new
        inst = Adapters::ActiveSupportNotificationsInstrumenter.new(notifier: notifier)

        calls = 0
        result =
          inst.instrument("agent_core.test", {}) do
            calls += 1
            "ok"
          end

        assert_equal "ok", result
        assert_equal 1, calls
      end

      def test_active_support_notifications_instrumenter_does_not_mask_block_error_when_notifier_raises_in_ensure
        require "agent_core/observability/adapters/active_support_notifications_instrumenter"

        notifier = ExplodingNotificationsInEnsure.new
        inst = Adapters::ActiveSupportNotificationsInstrumenter.new(notifier: notifier)

        calls = 0
        err =
          assert_raises(RuntimeError) do
            inst.instrument("agent_core.test", {}) do
              calls += 1
              raise "boom"
            end
          end

        assert_equal "boom", err.message
        assert_equal 1, calls
      end

      def test_active_support_notifications_instrumenter_records_error_and_reraises
        require "agent_core/observability/adapters/active_support_notifications_instrumenter"

        notifier = FakeNotifications.new
        inst = Adapters::ActiveSupportNotificationsInstrumenter.new(notifier: notifier)

        payload = { run_id: "r1" }
        err = assert_raises(RuntimeError) do
          inst.instrument("agent_core.test", payload) { raise "boom" }
        end
        assert_equal "boom", err.message

        assert payload[:error].is_a?(Hash)
        assert_equal "RuntimeError", payload[:error].fetch(:class)
        assert_equal "boom", payload[:error].fetch(:message)
        assert payload[:duration_ms].is_a?(Numeric)

        assert_equal 1, notifier.events.size
        event_payload = notifier.events.first.fetch(:payload)
        assert_equal "RuntimeError", event_payload.fetch(:error).fetch(:class)
      end

      def test_open_telemetry_instrumenter_creates_span_and_sets_attributes
        require "agent_core/observability/adapters/open_telemetry_instrumenter"

        tracer = FakeTracer.new
        inst = Adapters::OpenTelemetryInstrumenter.new(tracer: tracer)

        payload = { run_id: "r1", nested: { a: 1 } }
        result = inst.instrument("agent_core.test", payload) { "ok" }

        assert_equal "ok", result
        assert payload[:duration_ms].is_a?(Numeric)

        assert_equal 1, tracer.spans.size
        span = tracer.spans.first
        assert_equal "agent_core.test", span.fetch(:name)
        assert_equal "r1", span.fetch(:attributes).fetch("run_id")
        assert span.fetch(:attributes).fetch("nested").is_a?(String)
        assert span.fetch(:span).attributes.key?("duration_ms")
      end

      def test_open_telemetry_instrumenter_falls_back_when_tracer_raises_before_yield
        require "agent_core/observability/adapters/open_telemetry_instrumenter"

        tracer = ExplodingTracerBeforeYield.new
        inst = Adapters::OpenTelemetryInstrumenter.new(tracer: tracer)

        calls = 0
        result =
          inst.instrument("agent_core.test", {}) do
            calls += 1
            "ok"
          end

        assert_equal "ok", result
        assert_equal 1, calls
      end

      def test_open_telemetry_instrumenter_does_not_double_yield_when_tracer_raises_after_block
        require "agent_core/observability/adapters/open_telemetry_instrumenter"

        tracer = ExplodingTracerAfterYield.new
        inst = Adapters::OpenTelemetryInstrumenter.new(tracer: tracer)

        calls = 0
        result =
          inst.instrument("agent_core.test", {}) do
            calls += 1
            "ok"
          end

        assert_equal "ok", result
        assert_equal 1, calls
      end

      def test_open_telemetry_instrumenter_does_not_fail_when_span_set_attribute_raises
        require "agent_core/observability/adapters/open_telemetry_instrumenter"

        tracer = TracerWithExplodingSpan.new
        inst = Adapters::OpenTelemetryInstrumenter.new(tracer: tracer)

        calls = 0
        result =
          inst.instrument("agent_core.test", {}) do
            calls += 1
            "ok"
          end

        assert_equal "ok", result
        assert_equal 1, calls
      end

      def test_open_telemetry_instrumenter_records_exception_and_reraises
        require "agent_core/observability/adapters/open_telemetry_instrumenter"

        tracer = FakeTracer.new
        inst = Adapters::OpenTelemetryInstrumenter.new(tracer: tracer)

        payload = { run_id: "r1" }
        err = assert_raises(RuntimeError) do
          inst.instrument("agent_core.test", payload) { raise "boom" }
        end
        assert_equal "boom", err.message

        assert payload[:error].is_a?(Hash)
        assert_equal "RuntimeError", payload[:error].fetch(:class)

        span = tracer.spans.first.fetch(:span)
        assert_equal 1, span.exceptions.size
        assert_equal "boom", span.exceptions.first.message
        assert span.attributes.key?("error.class")
      end
    end
  end
end
