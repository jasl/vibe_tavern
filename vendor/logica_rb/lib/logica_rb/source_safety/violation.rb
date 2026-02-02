# frozen_string_literal: true

module LogicaRb
  module SourceSafety
    class Violation < LogicaRb::Error
      attr_reader :reason, :predicate_name

      def initialize(reason, message = nil, predicate_name: nil)
        @reason = reason
        @predicate_name = predicate_name
        super(message || reason.to_s)
      end
    end
  end
end
