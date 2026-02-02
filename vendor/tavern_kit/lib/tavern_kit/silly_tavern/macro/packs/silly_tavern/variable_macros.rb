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
              if !key.empty? && inv.environment.respond_to?(:set_var)
                inv.environment.set_var(key, coerce_number(value) || value.to_s, scope: :local)
              end
              ""
            end

            registry.register(
              "addvar",
              unnamed_args: [
                { name: "name", type: :string },
                { name: "value", type: %i[string number] },
              ],
            ) do |inv|
              name, value = Array(inv.args)
              key = name.to_s.strip
              next "" if key.empty?

              add_to_var(inv.environment, key, value, scope: :local)
              ""
            end

            registry.register(
              "incvar",
              unnamed_args: [
                { name: "name", type: :string },
              ],
            ) do |inv|
              name = Array(inv.args).first.to_s.strip
              increment_var(inv.environment, name, scope: :local, delta: 1)
            end

            registry.register(
              "decvar",
              unnamed_args: [
                { name: "name", type: :string },
              ],
            ) do |inv|
              name = Array(inv.args).first.to_s.strip
              increment_var(inv.environment, name, scope: :local, delta: -1)
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
              if !key.empty? && inv.environment.respond_to?(:set_var)
                inv.environment.set_var(key, coerce_number(value) || value.to_s, scope: :global)
              end
              ""
            end

            registry.register(
              "addglobalvar",
              unnamed_args: [
                { name: "name", type: :string },
                { name: "value", type: %i[string number] },
              ],
            ) do |inv|
              name, value = Array(inv.args)
              key = name.to_s.strip
              next "" if key.empty?

              add_to_var(inv.environment, key, value, scope: :global)
              ""
            end

            registry.register(
              "incglobalvar",
              unnamed_args: [
                { name: "name", type: :string },
              ],
            ) do |inv|
              name = Array(inv.args).first.to_s.strip
              increment_var(inv.environment, name, scope: :global, delta: 1)
            end

            registry.register(
              "decglobalvar",
              unnamed_args: [
                { name: "name", type: :string },
              ],
            ) do |inv|
              name = Array(inv.args).first.to_s.strip
              increment_var(inv.environment, name, scope: :global, delta: -1)
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

          def self.increment_var(env, name, scope:, delta:)
            return "" unless env.respond_to?(:get_var) && env.respond_to?(:set_var)

            key = name.to_s.strip
            return "" if key.empty?

            current = env.get_var(key, scope: scope)
            num = coerce_number(current) || 0
            next_val = num + delta.to_i
            env.set_var(key, next_val, scope: scope)
            normalize(next_val)
          end

          def self.add_to_var(env, name, value, scope:)
            return nil unless env.respond_to?(:get_var) && env.respond_to?(:set_var)

            current = env.get_var(name, scope: scope)
            rhs = coerce_number(value) || value.to_s
            cur_num = coerce_number(current)
            rhs_num = coerce_number(rhs)

            if !rhs_num.nil? && (current.nil? || !cur_num.nil?)
              env.set_var(name, (cur_num || 0) + rhs_num, scope: scope)
            else
              env.set_var(name, "#{current}#{rhs}", scope: scope)
            end
          end

          def self.coerce_number(value)
            return value if value.is_a?(Numeric)

            s = value.to_s.strip
            return nil if s.empty?

            if s.match?(/\A[-+]?\d+\z/)
              Integer(s, 10)
            else
              Float(s)
            end
          rescue ArgumentError, TypeError
            nil
          end

          def self.normalize(value)
            case value
            when Numeric
              return value.to_s if value.is_a?(Integer)

              f = value.to_f
              return f.to_i.to_s if f.finite? && (f % 1).zero?

              f.to_s
            when nil then ""
            when TrueClass then "true"
            when FalseClass then "false"
            else value.to_s
            end
          rescue StandardError
            ""
          end

          private_class_method :register_variable_macros, :add_to_var, :coerce_number, :increment_var, :normalize
        end
      end
    end
  end
end
