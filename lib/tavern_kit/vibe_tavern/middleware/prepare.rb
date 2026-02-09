# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module Middleware
      # Stage: defaults and input normalization.
      #
      # This is intentionally small: it sets up the context for the rest of the
      # pipeline without pulling in any ST/RisuAI behaviors.
      class Prepare < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          ctx.variables_store!

          normalize_runtime!(ctx)
          apply_token_estimation!(ctx)

          ctx.token_estimator ||= TavernKit::TokenEstimator.default
        end

        def normalize_runtime!(ctx)
          return if ctx.runtime
          return unless ctx.key?(:runtime)

          ctx.runtime = TavernKit::Runtime::Base.build(ctx[:runtime], type: :app)
        end

        def apply_token_estimation!(ctx)
          config = token_estimation_config(ctx) || {}

          apply_model_hint!(ctx, config)
          apply_token_estimator!(ctx, config) if config.any?
        end

        def token_estimation_config(ctx)
          runtime = ctx.runtime
          raw = runtime&.[](:token_estimation)
          raw = ctx[:token_estimation] if raw.nil? && ctx.key?(:token_estimation)

          return nil if raw.nil?

          raise ArgumentError, "token_estimation config must be a Hash" unless raw.is_a?(Hash)

          raw
        end

        def apply_model_hint!(ctx, config)
          explicit = ctx.key?(:model_hint) ? presence(ctx[:model_hint]) : nil

          runtime_hint = presence(config.fetch(:model_hint, nil))

          default_hint = ctx.key?(:default_model_hint) ? presence(ctx[:default_model_hint]) : nil

          selected = explicit || runtime_hint || default_hint
          return unless selected

          # Allow runtime to override a blank/invalid explicit hint.
          if explicit.nil?
            ctx[:model_hint] = selected.to_s
            ctx[:model_hint_source] =
              if runtime_hint
                :runtime
              elsif default_hint
                :default
              end
          end
        end

        def apply_token_estimator!(ctx, config)
          return if ctx.token_estimator

          estimator = config.fetch(:token_estimator, nil)
          if estimator
            raise ArgumentError, "token_estimation.token_estimator must respond to #estimate" unless estimator.respond_to?(:estimate)
            ctx.token_estimator = estimator
            ctx[:token_estimator_source] = :runtime
            return
          end

          registry = config.fetch(:registry, nil)
          return if registry.nil?

          raise ArgumentError, "token_estimation.registry must be a Hash" unless registry.is_a?(Hash)

          ctx.token_estimator = TavernKit::TokenEstimator.new(registry: registry)
          ctx[:token_estimator_source] = :runtime_registry
        end

        def presence(value)
          TavernKit::Utils.presence(value)
        end
      end
    end
  end
end
