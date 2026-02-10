# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module Preflight
      module_function

      def validate_request!(stream:, tools:, response_format:)
        if tools && response_format
          raise ArgumentError, "tools and response_format cannot be used in the same request"
        end

        if stream == true && (tools || response_format)
          raise ArgumentError, "streaming does not support tool calling or response_format"
        end
      end
    end
  end
end
