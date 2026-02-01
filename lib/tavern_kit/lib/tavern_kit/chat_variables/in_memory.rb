# frozen_string_literal: true

require_relative "../chat_variables"

module TavernKit
  module ChatVariables
    # In-memory ChatVariables implementation.
    class InMemory < Base
      def initialize
        @scopes = Hash.new { |h, k| h[k] = {} }
        @cache_version = 0
      end

      def get(name, scope: :local)
        @scopes[normalize_scope(scope)][normalize_name(name)]
      end

      def set(name, value, scope: :local)
        @cache_version += 1
        @scopes[normalize_scope(scope)][normalize_name(name)] = value
      end

      def has?(name, scope: :local)
        @scopes[normalize_scope(scope)].key?(normalize_name(name))
      end

      def delete(name, scope: :local)
        @cache_version += 1
        @scopes[normalize_scope(scope)].delete(normalize_name(name))
      end

      def add(name, value, scope: :local)
        @cache_version += 1
        scope_hash = @scopes[normalize_scope(scope)]
        key = normalize_name(name)

        current = scope_hash[key]
        if current.nil?
          scope_hash[key] = value
        elsif current.is_a?(Numeric) && value.is_a?(Numeric)
          scope_hash[key] = current + value
        else
          scope_hash[key] = "#{current}#{value}"
        end
      end

      def cache_version = @cache_version

      private

      def normalize_name(name)
        name.to_s
      end

      def normalize_scope(scope)
        scope.to_s.downcase.to_sym
      end
    end
  end
end
