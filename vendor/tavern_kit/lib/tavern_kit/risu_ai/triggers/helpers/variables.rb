# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Triggers
      module_function

      # Pure refactor: extracted from `risu_ai/triggers/helpers.rb`.
      def get_var(chat, name, local_vars:, current_indent:)
        key = name.to_s.delete_prefix("$")
        if local_vars
          local = local_vars.get(key, current_indent: current_indent)
          return local unless local.nil?
        end

        if (store = chat[:variables])
          if store.respond_to?(:get)
            value = store.get(key, scope: :local)
            return value unless value.nil?
          end
        end

        state = chat[:scriptstate]
        return nil unless state.is_a?(Hash)

        state["$#{key}"]
      end

      # Pure refactor: extracted from `risu_ai/triggers/helpers.rb`.
      def set_var(chat, name, value, local_vars:, current_indent:)
        key = name.to_s.delete_prefix("$")

        if local_vars && !local_vars.get(key, current_indent: current_indent).nil?
          local_vars.set(key, value, indent: current_indent)
          return
        end

        if (store = chat[:variables])
          store.set(key, value.to_s, scope: :local) if store.respond_to?(:set)
        end

        state = chat[:scriptstate]
        return unless state.is_a?(Hash) || store.nil?

        state ||= {}
        state["$#{key}"] = value.to_s
        chat[:scriptstate] = state
      end

      # Pure refactor: extracted from `risu_ai/triggers/helpers.rb`.
      def deep_symbolize(value)
        case value
        when Array
          value.map { |v| deep_symbolize(v) }
        when Hash
          value.each_with_object({}) do |(k, v), out|
            if k.is_a?(String) && k.start_with?("$")
              out[k] = deep_symbolize(v)
            else
              out[k.to_sym] = deep_symbolize(v)
            end
          end
        else
          value
        end
      end

      # Pure refactor: extracted from `risu_ai/triggers/helpers.rb`.
      def normalize_triggers(triggers)
        Array(triggers).filter_map do |raw|
          next nil unless raw.is_a?(Hash)

          TavernKit::Utils.deep_stringify_keys(raw)
        end
      end
      private_class_method :normalize_triggers
    end
  end
end
