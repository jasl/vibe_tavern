# frozen_string_literal: true

require "securerandom"

module AgentCore
  # Per-run execution context passed through the stack (runner/policy/tools).
  #
  # - run_id: stable identifier for correlating logs/traces/audits
  # - attributes: app-provided structured data (Symbol keys)
  # - instrumenter: library-agnostic observability backend
  # - clock/logger: optional helpers (pure Ruby, no Rails dependency)
  ExecutionContext =
    Data.define(
      :run_id,
      :attributes,
      :instrumenter,
      :clock,
      :logger,
    ) do
      class DefaultClock
        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def now
          Time.now
        end
      end

      def initialize(run_id: nil, attributes: {}, instrumenter: nil, clock: nil, logger: nil)
        rid = run_id.to_s.strip
        rid = SecureRandom.uuid if rid.empty?

        attrs = attributes.is_a?(Hash) ? attributes.dup : {}
        AgentCore::Utils.assert_symbol_keys!(attrs, path: "execution_context.attributes")
        attrs.freeze

        inst = instrumenter || AgentCore::Observability::NullInstrumenter.new
        unless inst.respond_to?(:instrument) && inst.respond_to?(:publish)
          raise ArgumentError, "instrumenter must respond to #instrument and #publish"
        end

        clk = clock || DefaultClock.new

        super(
          run_id: rid.freeze,
          attributes: attrs,
          instrumenter: inst,
          clock: clk,
          logger: logger,
        )
      end

      # Build/normalize a context from nil / Hash / ExecutionContext.
      #
      # Hash input must use Symbol keys (internal API).
      def self.from(value = nil, instrumenter: nil, **attributes)
        case value
        when nil
          if attributes.any?
            new(attributes: attributes, instrumenter: instrumenter)
          else
            new(instrumenter: instrumenter)
          end
        when self
          ctx = instrumenter ? value.with(instrumenter: instrumenter) : value
          return ctx if attributes.empty?

          merged = ctx.attributes.merge(attributes)
          ctx.with(attributes: merged)
        when Hash
          AgentCore::Utils.assert_symbol_keys!(value, path: "context")
          merged = attributes.empty? ? value : value.merge(attributes)
          new(attributes: merged, instrumenter: instrumenter)
        else
          raise ArgumentError, "context must be nil, a Hash (Symbol keys), or AgentCore::ExecutionContext (got #{value.class})"
        end
      end
    end
end
