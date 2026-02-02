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
          raw = metadata[:unnamed_args]
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
          raw = metadata[:list]
          return nil if raw.nil? || raw == false

          if raw == true
            { min: 0, max: nil }
          elsif raw.is_a?(Hash)
            min = raw.fetch(:min, 0)
            max = raw[:max]
            { min: min.to_i, max: max.nil? ? nil : max.to_i }
          else
            { min: 0, max: nil }
          end
        end

        def strict_args? = metadata.fetch(:strict_args, true) != false
        def delay_arg_resolution? = metadata[:delay_arg_resolution] == true

        def min_args
          unnamed_arg_defs.count do |defn|
            opt = defn.is_a?(Hash) ? defn[:optional] : nil
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
          meta = normalize_metadata_keys(metadata)

          meta[:unnamed_args] = unnamed_args if unnamed_args
          meta[:list] = list unless list.nil?
          meta[:strict_args] = strict_args
          meta[:delay_arg_resolution] = delay_arg_resolution

          # Normalize nested structures too so the rest of the macro engine only
          # deals with symbol keys.
          meta[:unnamed_args] = normalize_unnamed_args(meta[:unnamed_args]) if meta.key?(:unnamed_args)
          meta[:list] = normalize_list_spec(meta[:list]) if meta.key?(:list)

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

        def normalize_metadata_keys(hash)
          return {} unless hash.is_a?(Hash)

          hash.each_with_object({}) do |(k, v), out|
            out[TavernKit::Utils.underscore(k).to_sym] = v
          end
        end

        def normalize_unnamed_args(value)
          return value if value.is_a?(Integer)

          Array(value).map do |v|
            v.is_a?(Hash) ? normalize_metadata_keys(v) : v
          end
        end

        def normalize_list_spec(value)
          return value if value == true || value == false

          value.is_a?(Hash) ? normalize_metadata_keys(value) : value
        end
      end

      # Read-through registry wrapper for layering user-defined macros on top of built-ins.
      #
      # This keeps the macro engine simple (it only needs `#get`/`#has?`) while
      # allowing downstream apps to provide a registry via `ctx.macro_registry`.
      class RegistryChain < TavernKit::Macro::Registry::Base
        def initialize(*registries)
          @registries = registries.compact
        end

        def register(...) = primary.register(...)

        def get(name)
          @registries.each do |reg|
            next unless reg.respond_to?(:get)

            defn = reg.get(name)
            return defn if defn
          end

          nil
        end

        def has?(name)
          !get(name).nil?
        end

        private

        def primary
          reg = @registries.first
          raise ArgumentError, "No primary registry configured" unless reg
          raise ArgumentError, "Primary registry must respond to #register" unless reg.respond_to?(:register)

          reg
        end
      end
    end
  end
end
