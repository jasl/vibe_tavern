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
            :allowed_tools_enforcement,
            :allowed_tools_invalid_allowlist,
          ) do
            def self.disabled
              new(
                enabled: false,
                store: nil,
                include_location: false,
                allowed_tools_enforcement: :off,
                allowed_tools_invalid_allowlist: :ignore,
              )
            end

            def self.from_context(context)
              raw = context&.[](:skills)
              return disabled if raw.nil?

              raise ArgumentError, "context[:skills] must be a Hash" unless raw.is_a?(Hash)
              TavernKit::Utils.assert_symbol_keys!(raw, path: "context[:skills]")

              enabled = raw.fetch(:enabled, false) ? true : false
              include_location = raw.fetch(:include_location, false) ? true : false

              enforcement =
                if enabled
                  normalize_enforcement(raw.fetch(:allowed_tools_enforcement, :off))
                else
                  :off
                end

              invalid_allowlist =
                normalize_invalid_allowlist(raw.fetch(:allowed_tools_invalid_allowlist, :ignore))

              store = raw.fetch(:store, nil)
              if enabled
                raise ArgumentError, "skills.store is required when skills.enabled is true" if store.nil?
                raise ArgumentError, "skills.store must be a Tools::Skills::Store" unless store.is_a?(TavernKit::VibeTavern::Tools::Skills::Store)
              end

              new(
                enabled: enabled,
                store: store,
                include_location: include_location,
                allowed_tools_enforcement: enforcement,
                allowed_tools_invalid_allowlist: invalid_allowlist,
              )
            end

            def self.normalize_enforcement(value)
              mode = value.to_s.strip
              mode = "off" if mode.empty?
              mode = mode.downcase

              case mode
              when "off"
                :off
              when "enforce"
                :enforce
              else
                raise ArgumentError, "skills.allowed_tools_enforcement must be :off or :enforce"
              end
            end
            private_class_method :normalize_enforcement

            def self.normalize_invalid_allowlist(value)
              mode = value.to_s.strip
              mode = "ignore" if mode.empty?
              mode = mode.downcase

              case mode
              when "ignore"
                :ignore
              when "enforce"
                :enforce
              when "error"
                :error
              else
                raise ArgumentError, "skills.allowed_tools_invalid_allowlist must be :ignore, :enforce, or :error"
              end
            end
            private_class_method :normalize_invalid_allowlist
          end
      end
    end
  end
end
