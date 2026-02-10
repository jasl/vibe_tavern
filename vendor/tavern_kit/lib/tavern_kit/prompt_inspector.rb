# frozen_string_literal: true

require "json"

module TavernKit
  # Debug-only prompt inspection utilities.
  #
  # This is intentionally separate from the hot-path trimming/budgeting logic:
  # callers should keep using TokenEstimator#estimate for frequent token counts.
  class PromptInspector
    Totals =
      Data.define(
        :message_count,
        :content_tokens,
        :metadata_tokens,
        :overhead_tokens,
        :total_tokens,
      )

    MessageInspection =
      Data.define(
        :index,
        :role,
        :content_length,
        :content_tokenization,
        :metadata_token_count,
        :metadata_tokenization,
        :overhead_tokens,
        :total_tokens,
      )

    Inspection =
      Data.define(
        :estimator,
        :model_hint,
        :message_overhead_tokens,
        :include_message_metadata_tokens,
        :messages,
        :totals,
      )

    class << self
      def inspect_plan(
        plan,
        token_estimator: TavernKit::TokenEstimator.default,
        model_hint: nil,
        message_overhead_tokens: 0,
        include_message_metadata_tokens: false,
        include_metadata_details: false
      )
        unless plan.is_a?(TavernKit::Prompt::Plan)
          raise ArgumentError, "plan must be a TavernKit::Prompt::Plan"
        end

        inspect_messages(
          plan.messages,
          token_estimator: token_estimator,
          model_hint: model_hint,
          message_overhead_tokens: message_overhead_tokens,
          include_message_metadata_tokens: include_message_metadata_tokens,
          include_metadata_details: include_metadata_details,
        )
      end

      def inspect_messages(
        messages,
        token_estimator: TavernKit::TokenEstimator.default,
        model_hint: nil,
        message_overhead_tokens: 0,
        include_message_metadata_tokens: false,
        include_metadata_details: false
      )
        token_estimator ||= TavernKit::TokenEstimator.default
        unless token_estimator.respond_to?(:estimate)
          raise ArgumentError, "token_estimator must respond to #estimate"
        end

        overhead_per_message = Integer(message_overhead_tokens)
        raise ArgumentError, "message_overhead_tokens must be non-negative" if overhead_per_message.negative?

        tokenization_fn =
          if token_estimator.respond_to?(:tokenize)
            ->(text) { token_estimator.tokenize(text, model_hint: model_hint) }
          else
            ->(text) do
              TavernKit::TokenEstimator::Tokenization.new(
                backend: token_estimator.class.name,
                token_count: token_estimator.estimate(text, model_hint: model_hint),
              )
            end
          end

        messages = Array(messages).map { |m| normalize_message(m) }

        include_meta = include_message_metadata_tokens == true
        include_meta_details = include_metadata_details == true

        content_total = 0
        metadata_total = 0

        inspected =
          messages.each_with_index.map do |msg, idx|
            content = msg[:content].to_s

            content_tokenization = tokenization_fn.call(content)
            content_total += content_tokenization.token_count

            meta = msg[:metadata]
            meta_tokens = include_meta ? estimate_metadata_tokens(meta, token_estimator, model_hint) : 0
            metadata_total += meta_tokens

            meta_tokenization =
              if include_meta_details && include_meta && meta && !meta.empty?
                tokenization_fn.call(serialize_metadata(meta))
              end

            total = content_tokenization.token_count + meta_tokens + overhead_per_message

            MessageInspection.new(
              index: idx,
              role: msg[:role],
              content_length: content.length,
              content_tokenization: content_tokenization,
              metadata_token_count: meta_tokens,
              metadata_tokenization: meta_tokenization,
              overhead_tokens: overhead_per_message,
              total_tokens: total,
            )
          end

        overhead_total = overhead_per_message * messages.size

        estimator_info =
          if token_estimator.respond_to?(:describe)
            token_estimator.describe(model_hint: model_hint)
          else
            { backend: token_estimator.class.name }
          end

        totals =
          Totals.new(
            message_count: messages.size,
            content_tokens: content_total,
            metadata_tokens: metadata_total,
            overhead_tokens: overhead_total,
            total_tokens: content_total + metadata_total + overhead_total,
          )

        Inspection.new(
          estimator: estimator_info,
          model_hint: model_hint,
          message_overhead_tokens: overhead_per_message,
          include_message_metadata_tokens: include_meta,
          messages: inspected,
          totals: totals,
        )
      end

      private

      def normalize_message(message)
        case message
        when TavernKit::Prompt::Message
          {
            role: message.role,
            content: message.content,
            metadata: message.metadata,
          }
        when Hash
          message.each_key do |key|
            next if key.is_a?(Symbol)

            raise ArgumentError, "Hash messages must use Symbol keys (got: #{key.class})"
          end

          role_raw = message.fetch(:role, :unknown)
          role_s = role_raw.to_s.strip
          role = role_s.empty? ? :unknown : role_s.to_sym

          content = message.fetch(:content, "").to_s

          base_keys = %i[role content name].freeze
          metadata =
            message.each_with_object({}) do |(k, v), out|
              next if base_keys.include?(k)

              out[k] = v
            end
          metadata = nil if metadata.empty?

          { role: role, content: content, metadata: metadata }
        else
          raise ArgumentError, "message must be a TavernKit::Prompt::Message or a Hash"
        end
      end

      def estimate_metadata_tokens(meta, token_estimator, model_hint)
        return 0 unless meta.is_a?(Hash) && meta.any?

        token_estimator.estimate(serialize_metadata(meta), model_hint: model_hint)
      end

      def serialize_metadata(meta)
        JSON.generate(meta)
      rescue JSON::GeneratorError, TypeError
        meta.to_s
      end
    end
  end
end
