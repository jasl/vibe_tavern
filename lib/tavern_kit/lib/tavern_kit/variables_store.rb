# frozen_string_literal: true

module TavernKit
  # Generic, scoped key/value storage contract for prompt-building variables.
  #
  # This replaces the older "ChatVariables" naming: ST `var`/`globalvar` and
  # RisuAI's persisted variables are all variables stores with explicit scopes.
  module VariablesStore
    # Minimal variable storage contract for macro engines.
    #
    # Core guarantees :local and :global scopes. Platform layers may extend
    # scopes (e.g., RisuAI :temp / :function_arg), but those extra scopes are
    # typically implemented in the macro environment (ephemeral) rather than
    # the persisted store.
    class Base
      CORE_SCOPES = %i[local global].freeze

      def get(name, scope: :local) = raise NotImplementedError
      def set(name, value, scope: :local) = raise NotImplementedError
      def has?(name, scope: :local) = raise NotImplementedError
      def delete(name, scope: :local) = raise NotImplementedError
      def add(name, value, scope: :local) = raise NotImplementedError

      # Optional monotonic version for cache keying (nil when unsupported).
      def cache_version = nil
    end
  end
end
