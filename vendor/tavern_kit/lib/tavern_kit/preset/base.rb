# frozen_string_literal: true

module TavernKit
  module Preset
    # Minimal preset interface required by Core for budgeting decisions.
    class Base
      def context_window_tokens = raise NotImplementedError
      def reserved_response_tokens = raise NotImplementedError

      def max_prompt_tokens
        context_window_tokens.to_i - reserved_response_tokens.to_i
      end
    end
  end
end
