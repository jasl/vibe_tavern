# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      module Packs
        module SillyTavern
          def self.register_variable_macros(registry)
            registry.register(
              "setvar",
              unnamed_args: [
                { name: "name", type: :string },
                { name: "value", type: %i[string number] },
              ],
            ) do |inv|
              name, value = Array(inv.args)
              key = name.to_s.strip
              inv.environment.set_var(key, value.to_s, scope: :local) if !key.empty? && inv.environment.respond_to?(:set_var)
              ""
            end

            registry.register(
              "getvar",
              unnamed_args: [
                { name: "name", type: :string },
              ],
            ) do |inv|
              name = Array(inv.args).first.to_s.strip
              v = inv.environment.respond_to?(:get_var) ? inv.environment.get_var(name, scope: :local) : nil
              normalize(v)
            end

            registry.register(
              "hasvar",
              unnamed_args: [
                { name: "name", type: :string },
              ],
            ) do |inv|
              name = Array(inv.args).first.to_s.strip
              has = inv.environment.respond_to?(:has_var?) ? inv.environment.has_var?(name, scope: :local) : false
              has ? "true" : "false"
            end
            registry.register_alias("hasvar", "varexists")

            registry.register(
              "deletevar",
              unnamed_args: [
                { name: "name", type: :string },
              ],
            ) do |inv|
              name = Array(inv.args).first.to_s.strip
              inv.environment.delete_var(name, scope: :local) if inv.environment.respond_to?(:delete_var)
              ""
            end
            registry.register_alias("deletevar", "flushvar")

            registry.register(
              "setglobalvar",
              unnamed_args: [
                { name: "name", type: :string },
                { name: "value", type: %i[string number] },
              ],
            ) do |inv|
              name, value = Array(inv.args)
              key = name.to_s.strip
              inv.environment.set_var(key, value.to_s, scope: :global) if !key.empty? && inv.environment.respond_to?(:set_var)
              ""
            end

            registry.register(
              "getglobalvar",
              unnamed_args: [
                { name: "name", type: :string },
              ],
            ) do |inv|
              name = Array(inv.args).first.to_s.strip
              v = inv.environment.respond_to?(:get_var) ? inv.environment.get_var(name, scope: :global) : nil
              normalize(v)
            end

            registry.register(
              "hasglobalvar",
              unnamed_args: [
                { name: "name", type: :string },
              ],
            ) do |inv|
              name = Array(inv.args).first.to_s.strip
              has = inv.environment.respond_to?(:has_var?) ? inv.environment.has_var?(name, scope: :global) : false
              has ? "true" : "false"
            end
            registry.register_alias("hasglobalvar", "globalvarexists")

            registry.register(
              "deleteglobalvar",
              unnamed_args: [
                { name: "name", type: :string },
              ],
            ) do |inv|
              name = Array(inv.args).first.to_s.strip
              inv.environment.delete_var(name, scope: :global) if inv.environment.respond_to?(:delete_var)
              ""
            end
            registry.register_alias("deleteglobalvar", "flushglobalvar")
          end

          def self.normalize(value)
            case value
            when nil then ""
            when TrueClass then "true"
            when FalseClass then "false"
            else value.to_s
            end
          rescue StandardError
            ""
          end

          private_class_method :register_variable_macros, :normalize
        end
      end
    end
  end
end
