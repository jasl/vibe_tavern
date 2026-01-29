# frozen_string_literal: true

module TavernKit
  module HookRegistry
    class Base
      def before_build(&block) = raise NotImplementedError
      def after_build(&block) = raise NotImplementedError

      def run_before_build(ctx) = raise NotImplementedError
      def run_after_build(ctx) = raise NotImplementedError
    end
  end
end
