# frozen_string_literal: true

require "json"

require_relative "../step"

module TavernKit
  class PromptBuilder
    module Steps
      module MaxTokens
        extend TavernKit::PromptBuilder::Step

        Config =
          Data.define(
            :max_tokens,
            :reserve_tokens,
            :mode,
            :token_estimator,
            :model_hint,
            :message_overhead_tokens,
            :include_message_metadata_tokens,
          ) do
            def self.from_hash(raw)
              return raw if raw.is_a?(self)

              raise ArgumentError, "max_tokens step config must be a Hash" unless raw.is_a?(Hash)
              raw.each_key do |key|
                raise ArgumentError, "max_tokens step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
              end

              unknown = raw.keys - %i[
                max_tokens
                reserve_tokens
                mode
                token_estimator
                model_hint
                message_overhead_tokens
                include_message_metadata_tokens
              ]
              raise ArgumentError, "unknown max_tokens step config keys: #{unknown.inspect}" if unknown.any?

              max_tokens = raw.fetch(:max_tokens, nil)
              reserve_tokens = raw.fetch(:reserve_tokens, 0)
              mode = raw.fetch(:mode, :warn)
              token_estimator = raw.fetch(:token_estimator, nil)
              model_hint = raw.fetch(:model_hint, nil)
              message_overhead_tokens = raw.fetch(:message_overhead_tokens, 0)
              include_message_metadata_tokens = raw.fetch(:include_message_metadata_tokens, false)

              new(
                max_tokens: max_tokens,
                reserve_tokens: reserve_tokens,
                mode: mode,
                token_estimator: token_estimator,
                model_hint: model_hint,
                message_overhead_tokens: message_overhead_tokens,
                include_message_metadata_tokens: include_message_metadata_tokens,
              )
            end
          end

        def self.after(state, config)
          max_tokens = resolve_non_negative_int(config.max_tokens, state, allow_nil: true)
          return if max_tokens.nil? || max_tokens.zero?

          reserve_tokens = resolve_non_negative_int(config.reserve_tokens, state, allow_nil: false)
          limit_tokens = [max_tokens - reserve_tokens, 0].max

          estimation = estimate_prompt_tokens(state, config)
          prompt_tokens = estimation.fetch(:total)

          state.instrument(:stat, key: :estimated_prompt_tokens, value: prompt_tokens, step: state.current_step)
          state.instrument(:stat, key: :estimated_content_tokens, value: estimation.fetch(:content), step: state.current_step)
          state.instrument(:stat, key: :estimated_metadata_tokens, value: estimation.fetch(:metadata), step: state.current_step)
          state.instrument(:stat, key: :message_overhead_per_message_tokens, value: estimation.fetch(:overhead_per_message), step: state.current_step)
          state.instrument(:stat, key: :message_overhead_tokens, value: estimation.fetch(:overhead_total), step: state.current_step)
          state.instrument(:stat, key: :message_count, value: estimation.fetch(:message_count), step: state.current_step)
          state.instrument(:stat, key: :max_prompt_tokens, value: limit_tokens, step: state.current_step)

          return if prompt_tokens <= limit_tokens

          mode = resolve_mode(config.mode, state)

          case mode
          when :warn
            state.warn(exceeded_message(prompt_tokens, limit_tokens, max_tokens, reserve_tokens))
          when :error
            raise TavernKit::MaxTokensExceededError.new(
              estimated_tokens: prompt_tokens,
              max_tokens: max_tokens,
              reserve_tokens: reserve_tokens,
              step: state.current_step || step_name,
            )
          when :off, :none, nil
            nil
          else
            raise ArgumentError, "Unknown mode: #{mode.inspect} (expected :warn or :error)"
          end
        end

        class << self
          private

          def exceeded_message(prompt_tokens, limit_tokens, max_tokens, reserve_tokens)
            format(
              "Prompt estimated tokens %d exceeded limit %d (max_tokens: %d, reserve_tokens: %d)",
              prompt_tokens,
              limit_tokens,
              max_tokens,
              reserve_tokens,
            )
          end

          def estimate_prompt_tokens(state, config)
            estimator = config.token_estimator || state.token_estimator || TavernKit::TokenEstimator.default
            model_hint = resolve_value(config.model_hint.nil? ? state[:model_hint] : config.model_hint, state)
            overhead_per_message = resolve_non_negative_int(config.message_overhead_tokens, state, allow_nil: true) || 0
            include_metadata_tokens = resolve_value(config.include_message_metadata_tokens, state) == true

            if estimator.respond_to?(:describe)
              state.instrument(:stat, key: :token_estimator, step: state.current_step) do
                { value: estimator.describe(model_hint: model_hint) }
              end
            end

            messages = if state.plan
              state.plan.messages
            elsif state.blocks
              Array(state.blocks).select(&:enabled?).map(&:to_message)
            else
              []
            end

            content_tokens = messages.sum do |msg|
              estimator.estimate(msg.content.to_s, model_hint: model_hint)
            end

            metadata_tokens = if include_metadata_tokens
              messages.sum do |msg|
                estimate_message_metadata_tokens(msg, estimator: estimator, model_hint: model_hint)
              end
            else
              0
            end

            overhead_tokens = overhead_per_message * messages.size

            {
              content: content_tokens,
              metadata: metadata_tokens,
              overhead_per_message: overhead_per_message,
              overhead_total: overhead_tokens,
              message_count: messages.size,
              total: content_tokens + metadata_tokens + overhead_tokens,
            }
          end

          def estimate_message_metadata_tokens(message, estimator:, model_hint:)
            meta = message.metadata
            return 0 unless meta.is_a?(Hash) && meta.any?

            serialized =
              begin
                JSON.generate(meta)
              rescue JSON::GeneratorError, TypeError
                meta.to_s
              end

            estimator.estimate(serialized, model_hint: model_hint)
          end

          def resolve_value(value, state)
            value.respond_to?(:call) ? value.call(state) : value
          end

          def resolve_non_negative_int(value, state, allow_nil:)
            resolved = resolve_value(value, state)
            return nil if allow_nil && resolved.nil?

            int = Integer(resolved)
            raise ArgumentError, "Expected a non-negative Integer, got: #{resolved.inspect}" if int.negative?

            int
          rescue ArgumentError, TypeError
            raise ArgumentError, "Expected a non-negative Integer, got: #{resolved.inspect}"
          end

          def resolve_mode(value, state)
            resolved = resolve_value(value, state)
            resolved.nil? ? nil : resolved.to_sym
          end
        end
      end
    end
  end
end
