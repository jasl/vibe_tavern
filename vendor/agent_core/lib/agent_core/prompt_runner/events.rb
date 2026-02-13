# frozen_string_literal: true

module AgentCore
  module PromptRunner
    # Callback-based event system for the runner.
    #
    # Allows callers to observe the runner's lifecycle without coupling
    # to a specific logging or instrumentation framework.
    #
    # @example
    #   events = Events.new
    #   events.on_turn_start { |turn| puts "Turn #{turn}" }
    #   events.on_tool_call { |name, args, id| puts "Calling #{name}" }
    class Events
      HOOKS = %i[
        turn_start
        turn_end
        llm_request
        llm_response
        tool_call
        tool_result
        stream_delta
        error
      ].freeze

      def initialize
        @callbacks = {}
        HOOKS.each { |hook| @callbacks[hook] = [] }
      end

      # Register callbacks via on_* methods.
      HOOKS.each do |hook|
        define_method(:"on_#{hook}") do |&block|
          @callbacks[hook] << block if block
          self
        end
      end

      # Generic hook registration by name.
      # @param hook [Symbol] Hook name (must be one of HOOKS)
      # @param block [Proc] Callback
      # @return [self]
      def on(hook, &block)
        raise ArgumentError, "Unknown hook: #{hook}" unless @callbacks.key?(hook)
        @callbacks[hook] << block if block
        self
      end

      # Emit an event to all registered callbacks.
      # Each callback runs independently — one failure does not block others.
      # @param hook [Symbol] Event name
      # @param args [Array] Arguments to pass to callbacks
      def emit(hook, *args)
        @callbacks.fetch(hook, []).each do |cb|
          cb.call(*args)
        rescue => e
          next if hook == :error # prevent infinite recursion
          @callbacks[:error].each { |ecb| ecb.call(e, true) } if @callbacks[:error].any?
        end
      end

      # Whether any callbacks are registered for a hook.
      def has_listeners?(hook)
        @callbacks.fetch(hook, []).any?
      end
    end
  end
end
