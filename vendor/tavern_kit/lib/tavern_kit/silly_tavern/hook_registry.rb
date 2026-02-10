# frozen_string_literal: true

module TavernKit
  module SillyTavern
    # Simple in-memory hook registry.
    #
    # Hooks are intentionally low-level and receive PromptBuilder::Context directly.
    class HookRegistry < TavernKit::HookRegistry::Base
      def initialize
        @before = []
        @after = []
      end

      def before_build(&block)
        raise ArgumentError, "block required" unless block

        @before << block
        self
      end

      def after_build(&block)
        raise ArgumentError, "block required" unless block

        @after << block
        self
      end

      def run_before_build(ctx)
        @before.each { |h| h.call(ctx) }
      end

      def run_after_build(ctx)
        @after.each { |h| h.call(ctx) }
      end
    end
  end
end
