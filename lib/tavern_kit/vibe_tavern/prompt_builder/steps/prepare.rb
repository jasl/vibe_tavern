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

          def self.before(ctx, _config)
            ctx.variables_store!

            apply_token_estimation!(ctx)

            ctx.token_estimator ||= TavernKit::VibeTavern::TokenEstimation.estimator
          end

          class << self
            private

            def apply_token_estimation!(ctx)
            token_estimation = token_estimation_config(ctx) || {}

            apply_model_hint!(ctx, token_estimation)
            apply_token_estimator!(ctx, token_estimation)
            end

            def token_estimation_config(ctx)
            context = ctx.context
            token_estimation = context&.[](:token_estimation)

            return nil if token_estimation.nil?

            raise ArgumentError, "token_estimation config must be a Hash" unless token_estimation.is_a?(Hash)

            token_estimation
            end

            def apply_model_hint!(ctx, token_estimation)
            explicit_hint = ctx.key?(:model_hint) ? presence(ctx[:model_hint]) : nil

            # Allow context to override a blank/invalid explicit hint.
            return if explicit_hint

            context_hint = presence(token_estimation.fetch(:model_hint, nil))

            default_hint = ctx.key?(:default_model_hint) ? presence(ctx[:default_model_hint]) : nil

            selected_hint = context_hint || default_hint
            return unless selected_hint

            ctx[:model_hint] = TavernKit::VibeTavern::TokenEstimation.canonical_model_hint(selected_hint)
            ctx[:model_hint_source] = context_hint ? :context : :default
            end

            def apply_token_estimator!(ctx, token_estimation)
            return if ctx.token_estimator

            token_estimator = token_estimation.fetch(:token_estimator, nil)
            if token_estimator
              raise ArgumentError, "token_estimation.token_estimator must respond to #estimate" unless token_estimator.respond_to?(:estimate)
              ctx.token_estimator = token_estimator
              ctx[:token_estimator_source] = :context
              return
            end

            registry = token_estimation.fetch(:registry, nil)
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
end
