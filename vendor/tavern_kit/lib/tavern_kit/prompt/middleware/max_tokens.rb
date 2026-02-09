# frozen_string_literal: true

require "json"

require_relative "base"

module TavernKit
  module Prompt
    module Middleware
      class MaxTokensMiddleware < Base
        private

        def after(ctx)
          max_tokens = resolve_non_negative_int(option(:max_tokens), ctx, allow_nil: true)
          return if max_tokens.nil? || max_tokens.zero?

          reserve_tokens = resolve_non_negative_int(option(:reserve_tokens, 0), ctx, allow_nil: false)
          limit_tokens = [max_tokens - reserve_tokens, 0].max

          estimation = estimate_prompt_tokens(ctx)
          prompt_tokens = estimation.fetch(:total)

          if ctx.instrumenter
            ctx.instrument(:stat, key: :estimated_prompt_tokens, value: prompt_tokens, stage: ctx.current_stage)
            ctx.instrument(:stat, key: :estimated_content_tokens, value: estimation.fetch(:content), stage: ctx.current_stage)
            ctx.instrument(:stat, key: :estimated_metadata_tokens, value: estimation.fetch(:metadata), stage: ctx.current_stage)
            ctx.instrument(:stat, key: :message_overhead_per_message_tokens, value: estimation.fetch(:overhead_per_message), stage: ctx.current_stage)
            ctx.instrument(:stat, key: :message_overhead_tokens, value: estimation.fetch(:overhead_total), stage: ctx.current_stage)
            ctx.instrument(:stat, key: :message_count, value: estimation.fetch(:message_count), stage: ctx.current_stage)
            ctx.instrument(:stat, key: :max_prompt_tokens, value: limit_tokens, stage: ctx.current_stage)
          end

          return if prompt_tokens <= limit_tokens

          mode = resolve_mode(option(:mode, :warn), ctx)
          message = format(
            "Prompt estimated tokens %d exceeded limit %d (max_tokens: %d, reserve_tokens: %d)",
            prompt_tokens,
            limit_tokens,
            max_tokens,
            reserve_tokens,
          )

          case mode
          when :warn
            ctx.warn(message)
          when :error
            raise TavernKit::MaxTokensExceededError.new(
              estimated_tokens: prompt_tokens,
              max_tokens: max_tokens,
              reserve_tokens: reserve_tokens,
              stage: option(:__stage, self.class.middleware_name),
            )
          when :off, :none, nil
            nil
          else
            raise ArgumentError, "Unknown mode: #{mode.inspect} (expected :warn or :error)"
          end
        end

        def estimate_prompt_tokens(ctx)
          estimator = option(:token_estimator) || ctx.token_estimator || TavernKit::TokenEstimator.default
          model_hint = resolve_value(option(:model_hint, ctx[:model_hint]), ctx)
          overhead_per_message = resolve_non_negative_int(option(:message_overhead_tokens, 0), ctx, allow_nil: true) || 0
          include_metadata_tokens = resolve_value(option(:include_message_metadata_tokens, false), ctx) == true

          if ctx.instrumenter && estimator.respond_to?(:describe)
            ctx.instrument(:stat, key: :token_estimator, value: estimator.describe(model_hint: model_hint), stage: ctx.current_stage)
          end

          messages = if ctx.plan
            ctx.plan.messages
          elsif ctx.blocks
            Array(ctx.blocks).select(&:enabled?).map(&:to_message)
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

        def resolve_value(value, ctx)
          value.respond_to?(:call) ? value.call(ctx) : value
        end

        def resolve_non_negative_int(value, ctx, allow_nil:)
          resolved = resolve_value(value, ctx)
          return nil if allow_nil && resolved.nil?

          int = Integer(resolved)
          raise ArgumentError, "Expected a non-negative Integer, got: #{resolved.inspect}" if int.negative?

          int
        rescue ArgumentError, TypeError
          raise ArgumentError, "Expected a non-negative Integer, got: #{resolved.inspect}"
        end

        def resolve_mode(value, ctx)
          resolved = resolve_value(value, ctx)
          resolved.nil? ? nil : resolved.to_sym
        end
      end
    end
  end
end
