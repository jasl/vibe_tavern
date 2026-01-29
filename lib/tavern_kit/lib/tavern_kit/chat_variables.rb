# frozen_string_literal: true

module TavernKit
  module ChatVariables
    # Minimal variable storage contract for macro engines.
    #
    # Core guarantees :local and :global scopes. Platform layers may extend
    # scopes (e.g., RisuAI :temp / :function_arg).
    class Base
      CORE_SCOPES = %i[local global].freeze

      def get(name, scope: :local) = raise NotImplementedError
      def set(name, value, scope: :local) = raise NotImplementedError
      def has?(name, scope: :local) = raise NotImplementedError
      def delete(name, scope: :local) = raise NotImplementedError
      def add(name, value, scope: :local) = raise NotImplementedError
    end
  end
end
