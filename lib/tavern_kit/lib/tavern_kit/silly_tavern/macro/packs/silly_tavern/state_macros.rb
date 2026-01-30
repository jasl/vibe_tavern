# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      module Packs
        module SillyTavern
          def self.register_state_macros(registry)
            registry.register("lastGenerationType") do |inv|
              attrs = inv.environment.respond_to?(:platform_attrs) ? inv.environment.platform_attrs : {}
              TavernKit::Utils::HashAccessor.wrap(attrs).fetch(:last_generation_type, :lastGenerationType, default: "").to_s
            end

            registry.register(
              "hasExtension",
              unnamed_args: [
                { name: "extensionName", type: :string },
              ],
            ) do |inv|
              name = Array(inv.args).first.to_s.strip
              next "false" if name.empty?

              attrs = inv.environment.respond_to?(:platform_attrs) ? inv.environment.platform_attrs : {}
              ha = TavernKit::Utils::HashAccessor.wrap(attrs)

              value =
                ha.fetch(:extensions_enabled, :extensionsEnabled, :enabled_extensions, default: nil) ||
                  ha.fetch(:extensions, default: nil)

              case value
              when Hash
                enabled = value[name] || value[name.to_s] || value[name.to_sym]
                enabled ? "true" : "false"
              when Array
                value.map(&:to_s).include?(name) ? "true" : "false"
              else
                "false"
              end
            end
          end

          private_class_method :register_state_macros
        end
      end
    end
  end
end
