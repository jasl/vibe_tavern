# frozen_string_literal: true

module AgentCore
  module Contrib
    module TokenCounter
      class HeuristicWithOverhead < AgentCore::Resources::TokenCounter::Heuristic
        attr_reader :per_message_overhead

        def initialize(per_message_overhead:, **heuristic_kwargs)
          overhead = Integer(per_message_overhead, exception: false)
          raise ArgumentError, "per_message_overhead must be a non-negative Integer" unless overhead && overhead >= 0

          @per_message_overhead = overhead
          super(**heuristic_kwargs)
        end

        def count_messages(messages)
          super(messages, per_message_overhead: per_message_overhead)
        end
      end
    end
  end
end
