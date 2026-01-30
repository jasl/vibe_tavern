# frozen_string_literal: true

module TavernKit
  module Prompt
    module Middleware
      # Base class for all prompt pipeline middlewares.
      #
      # Middlewares follow the Rack-style pattern: each middleware wraps the
      # next one in the chain, receives a context, can modify it before and
      # after passing to the next middleware.
      #
      # @example Simple middleware
      #   class LoggingMiddleware < TavernKit::Prompt::Middleware::Base
      #     private
      #
      #     def before(ctx)
      #       puts "Before: #{ctx.user_message}"
      #     end
      #
      #     def after(ctx)
      #       puts "After: #{ctx.blocks.size} blocks"
      #     end
      #   end
      #
      class Base
        # @return [#call] the next middleware or terminal handler
        attr_reader :app

        # @return [Hash] middleware options
        attr_reader :options

        # @param app [#call] next middleware in chain
        # @param options [Hash] middleware-specific options
        def initialize(app, **options)
          @app = app
          @options = options
        end

        # Process the context through this middleware.
        #
        # Calls {#before}, then passes to the next middleware,
        # then calls {#after}.
        #
        # @param ctx [Context] the prompt context
        # @return [Context] the processed context
        def call(ctx)
          stage = option(:__stage, self.class.middleware_name)
          prev_stage = ctx.current_stage
          ctx.current_stage = stage

          ctx.instrument(:middleware_start, name: stage) if ctx.instrumenter
          before(ctx)
          @app.call(ctx)
          after(ctx)
          ctx.instrument(:middleware_finish, name: stage) if ctx.instrumenter
          ctx
        rescue => e
          ctx.instrument(:middleware_error, name: stage, error: e) if ctx&.instrumenter

          raise e if e.is_a?(TavernKit::PipelineError)

          raise TavernKit::PipelineError.new("#{e.class}: #{e.message}", stage: stage), cause: e
        ensure
          ctx.current_stage = prev_stage if ctx
        end

        # Class method to get the middleware name for registration.
        #
        # @return [Symbol]
        def self.middleware_name
          name.split("::").last.gsub(/Middleware$/, "").gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
        end

        private

        # Hook called before passing to next middleware.
        # @param ctx [Context]
        def before(ctx)
          # Override in subclass
        end

        # Hook called after next middleware returns.
        # @param ctx [Context]
        def after(ctx)
          # Override in subclass
        end

        # Helper to access an option with default.
        def option(key, default = nil)
          @options.fetch(key, default)
        end
      end
    end
  end
end
