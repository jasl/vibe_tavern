# frozen_string_literal: true

require "thread"

module TavernKit
  # Minimal Rails-like load hooks for wiring up app-specific infrastructure.
  #
  # Design goals:
  # - No ActiveSupport dependency
  # - Thread-safe registration/execution
  # - Idempotent registration via `id:` (recommended for reloadable code)
  #
  # Semantics:
  # - `run_load_hooks(scope, payload)` sets/replaces the current payload and
  #   executes all hooks registered for that scope.
  # - `on_load(scope)` registers a hook; if the scope has already been run, the
  #   hook is executed immediately with the current payload.
  module LoadHooks
    module_function

    def on_load(scope, id: nil, &block)
      raise ArgumentError, "block required" unless block

      scope = scope.to_sym
      hook_id = id&.to_sym

      payload = nil
      mutex.synchronize do
        entry = hooks_for(scope)
        if hook_id
          entry[:named][hook_id] = block
        else
          entry[:anonymous] << block
        end

        payload = payloads[scope]
      end

      block.call(payload) if payload

      block
    end

    def run_load_hooks(scope, payload)
      scope = scope.to_sym

      hook_list = nil
      mutex.synchronize do
        payloads[scope] = payload
        entry = hooks_for(scope)
        hook_list = entry[:named].values + entry[:anonymous]
      end

      hook_list.each { |hook| hook.call(payload) }

      payload
    end

    def reset!(scope = nil)
      mutex.synchronize do
        if scope
          scope = scope.to_sym
          hooks.delete(scope)
          payloads.delete(scope)
        else
          hooks.clear
          payloads.clear
        end
      end
    end

    def mutex
      @mutex ||= Mutex.new
    end
    private_class_method :mutex

    def hooks
      @hooks ||= {}
    end
    private_class_method :hooks

    def payloads
      @payloads ||= {}
    end
    private_class_method :payloads

    def hooks_for(scope)
      hooks[scope] ||= { named: {}, anonymous: [] }
    end
    private_class_method :hooks_for
  end
end

