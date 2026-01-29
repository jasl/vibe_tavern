# frozen_string_literal: true

module TavernKit
  module Lore
    # Minimal shared scan input -- platform layers can extend via subclass
    # (or by passing additional keyword args and reading them elsewhere).
    class ScanInput
      attr_reader :messages, :books, :budget

      def initialize(messages:, books:, budget:, **_platform_attrs)
        @messages = messages
        @books = books
        @budget = budget
      end
    end
  end
end
