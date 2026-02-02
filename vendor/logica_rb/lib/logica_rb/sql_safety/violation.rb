# frozen_string_literal: true

module LogicaRb
  module SqlSafety
    class Violation < LogicaRb::Error
      attr_reader :reason, :details

      def initialize(reason, message = nil, details: nil)
        @reason = reason
        @details = details
        super(message || reason.to_s)
      end
    end
  end
end
