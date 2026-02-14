# frozen_string_literal: true

module AgentCore
  module Contrib
    module TokenCounter
      class Estimator < AgentCore::Resources::TokenCounter::Base
        attr_reader :token_estimator, :model_hint, :per_message_overhead

        def initialize(token_estimator:, model_hint: nil, per_message_overhead: 0)
          unless token_estimator.respond_to?(:estimate)
            raise ArgumentError, "token_estimator must respond to #estimate"
          end

          overhead = Integer(per_message_overhead, exception: false)
          raise ArgumentError, "per_message_overhead must be a non-negative Integer" unless overhead && overhead >= 0

          @token_estimator = token_estimator
          @model_hint = model_hint
          @per_message_overhead = overhead
        end

        def count_text(text)
          estimated = token_estimator.estimate(text.to_s, model_hint: model_hint)
          Integer(estimated, exception: false) || 0
        end

        def count_messages(messages)
          super(messages, per_message_overhead: per_message_overhead)
        end
      end
    end
  end
end
