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
      )

      # Registry for SillyTavern macros.
      #
      # - Case-insensitive lookup
      # - Optional aliases (for doc/autocomplete parity later)
      # - Metadata is opaque to Core and can evolve without breaking callers
      class Registry < TavernKit::Macro::Registry::Base
        def initialize
          @entries = {}
        end

        def register(name, handler = nil, **metadata, &block)
          fn = block || handler
          raise ArgumentError, "Macro handler is required" if fn.nil?

          key = normalize_name(name)
          defn = Definition.new(
            name: key,
            handler: fn,
            metadata: metadata.freeze,
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
