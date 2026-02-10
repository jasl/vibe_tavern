# frozen_string_literal: true

require_relative "../../token_estimation"

module TavernKit
  module VibeTavern
    module PromptBuilder
      module Steps
        # Step: defaults and input normalization.
        #
        # This is intentionally small: it sets up the context for the rest of the
        # pipeline without pulling in any ST/RisuAI behaviors.
        class Prepare < TavernKit::PromptBuilder::Step
          Config =
            Data.define do
              def self.from_hash(raw)
                return raw if raw.is_a?(self)

                raise ArgumentError, "prepare step config must be a Hash" unless raw.is_a?(Hash)
                raw.each_key do |key|
                  raise ArgumentError, "prepare step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
                end

                if raw.any?
                  raise ArgumentError, "prepare step does not accept step config keys: #{raw.keys.inspect}"
                end

                new
              end
            end

          private

          def before(ctx)
            cfg = option(:config)
            raise ArgumentError, "prepare step config must be Steps::Prepare::Config" unless cfg.is_a?(Config)

            ctx.variables_store!

            apply_token_estimation!(ctx)

            ctx.token_estimator ||= TavernKit::VibeTavern::TokenEstimation.estimator
          end

          def apply_token_estimation!(ctx)
            config = token_estimation_config(ctx) || {}

            apply_model_hint!(ctx, config)
            apply_token_estimator!(ctx, config) if config.any?
          end

          def token_estimation_config(ctx)
            context = ctx.context
            raw = context&.[](:token_estimation)

            return nil if raw.nil?

            raise ArgumentError, "token_estimation config must be a Hash" unless raw.is_a?(Hash)

            raw
          end

          def apply_model_hint!(ctx, config)
            explicit = ctx.key?(:model_hint) ? presence(ctx[:model_hint]) : nil

            context_hint = presence(config.fetch(:model_hint, nil))

            default_hint = ctx.key?(:default_model_hint) ? presence(ctx[:default_model_hint]) : nil

            selected = explicit || context_hint || default_hint
            return unless selected

            # Allow context to override a blank/invalid explicit hint.
            if explicit.nil?
              ctx[:model_hint] = TavernKit::VibeTavern::TokenEstimation.canonical_model_hint(selected)
              ctx[:model_hint_source] =
                if context_hint
                  :context
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
              ctx[:token_estimator_source] = :context
              return
            end

            registry = config.fetch(:registry, nil)
            return if registry.nil?

            raise ArgumentError, "token_estimation.registry must be a Hash" unless registry.is_a?(Hash)

            ctx.token_estimator = TavernKit::TokenEstimator.new(registry: registry)
            ctx[:token_estimator_source] = :context_registry
          end

          def presence(value)
            TavernKit::Utils.presence(value)
          end
        end
      end
    end
  end
end
