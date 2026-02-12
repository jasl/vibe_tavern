# frozen_string_literal: true

require_relative "store"

module TavernKit
  module VibeTavern
    module Tools
      module Skills
        Config =
          Data.define(
            :enabled,
            :store,
            :include_location,
          ) do
            def self.disabled
              new(
                enabled: false,
                store: nil,
                include_location: false,
              )
            end

            def self.from_context(context)
              raw = context&.[](:skills)
              return disabled if raw.nil?

              raise ArgumentError, "context[:skills] must be a Hash" unless raw.is_a?(Hash)
              TavernKit::Utils.assert_symbol_keys!(raw, path: "context[:skills]")

              enabled = raw.fetch(:enabled, false) ? true : false
              include_location = raw.fetch(:include_location, false) ? true : false

              store = raw.fetch(:store, nil)
              if enabled
                raise ArgumentError, "skills.store is required when skills.enabled is true" if store.nil?
                raise ArgumentError, "skills.store must be a Tools::Skills::Store" unless store.is_a?(TavernKit::VibeTavern::Tools::Skills::Store)
              end

              new(
                enabled: enabled,
                store: store,
                include_location: include_location,
              )
            end
          end
      end
    end
  end
end
