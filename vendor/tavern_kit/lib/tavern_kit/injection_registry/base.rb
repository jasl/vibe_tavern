# frozen_string_literal: true

module TavernKit
  module InjectionRegistry
    class Base
      def register(id:, content:, position:, **opts) = raise NotImplementedError
      def remove(id:) = raise NotImplementedError
      def each(&block) = raise NotImplementedError
      def ephemeral_ids = raise NotImplementedError
    end
  end
end
