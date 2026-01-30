# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      Definition = Data.define(
        :name,
        :handler,
        :metadata,
        :alias_of,
        :alias_visible,
      ) do
        def unnamed_arg_defs
          raw = metadata[:unnamed_args] || metadata["unnamed_args"] || metadata[:unnamedArgs] || metadata["unnamedArgs"]
          case raw
          when nil
            []
          when Integer
            # ST supports unnamedArgs as a number (all required). Default to
            # string type for validation/docs parity.
            Array.new(raw) { { name: nil, optional: false, type: :string } }
          else
            Array(raw)
          end
        end

        def list_spec
          raw = metadata[:list] || metadata["list"]
          return nil if raw.nil? || raw == false

          if raw == true
            { min: 0, max: nil }
          elsif raw.is_a?(Hash)
            min = raw[:min] || raw["min"] || 0
            max = raw[:max] || raw["max"]
            { min: min.to_i, max: max.nil? ? nil : max.to_i }
          else
            { min: 0, max: nil }
          end
        end

        def strict_args? = (metadata.key?(:strict_args) ? metadata[:strict_args] : metadata["strict_args"]) != false
        def delay_arg_resolution? = (metadata[:delay_arg_resolution] || metadata["delay_arg_resolution"]) == true

        def min_args
          unnamed_arg_defs.count do |defn|
            opt = defn.is_a?(Hash) ? (defn[:optional] || defn["optional"]) : nil
            opt != true
          end
        end

        def max_args
          unnamed_arg_defs.length
        end

        def arity_valid?(arg_count)
          count = arg_count.to_i
          list = list_spec

          if list.nil?
            count >= min_args && count <= max_args
          else
            min_required = min_args + list.fetch(:min, 0).to_i
            return false if count < min_required

            list_count = [count - max_args, 0].max
            max_list = list[:max]
            max_list.nil? ? true : list_count <= max_list.to_i
          end
        end

        # ST's scoped macro pairing checks if adding 1 scoped-content argument
        # would be valid for this macro's arity.
        def accepts_scoped_content?(current_arg_count)
          arity_valid?(current_arg_count.to_i + 1)
        end
      end

      # Registry for SillyTavern macros.
      #
      # - Case-insensitive lookup
      # - Optional aliases (for doc/autocomplete parity later)
      # - Metadata is opaque to Core and can evolve without breaking callers
      class Registry < TavernKit::Macro::Registry::Base
        def initialize
          @entries = {}
        end

        def register(
          name,
          handler = nil,
          unnamed_args: nil,
          list: nil,
          strict_args: true,
          delay_arg_resolution: false,
          **metadata,
          &block
        )
          fn = block || handler
          raise ArgumentError, "Macro handler is required" if fn.nil?

          key = normalize_name(name)
          meta = metadata.dup
          meta[:unnamed_args] = unnamed_args if unnamed_args
          meta[:list] = list unless list.nil?
          meta[:strict_args] = strict_args
          meta[:delay_arg_resolution] = delay_arg_resolution

          defn = Definition.new(
            name: key,
            handler: fn,
            metadata: meta.freeze,
            alias_of: nil,
            alias_visible: nil,
          )

          @entries[key] = defn
          self
        end

        def register_alias(target_name, alias_name, visible: true)
          target_key = normalize_name(target_name)
          target = @entries[target_key]
          raise ArgumentError, "Macro is not registered: #{target_name.inspect}" unless target

          alias_key = normalize_name(alias_name)
          defn = Definition.new(
            name: alias_key,
            handler: target.handler,
            metadata: target.metadata,
            alias_of: target_key,
            alias_visible: visible == true,
          )

          @entries[alias_key] = defn
          self
        end

        def get(name)
          @entries[normalize_name(name)]
        end

        def has?(name)
          @entries.key?(normalize_name(name))
        end

        private

        def normalize_name(name)
          s = name.to_s.strip
          raise ArgumentError, "Macro name must not be empty" if s.empty?

          s.downcase
        end
      end
    end
  end
end
