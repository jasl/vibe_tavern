# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      module Packs
        # Built-in macro pack aiming for SillyTavern parity (Wave 3).
        #
        # This file intentionally starts small and grows with tests. Avoid adding
        # macros without a corresponding spec/characterization test.
        module SillyTavern
          def self.default_registry
            @default_registry ||= begin
              registry = TavernKit::SillyTavern::Macro::Registry.new
              register(registry)
              registry
            end
          end

          def self.register(registry)
            register_core_macros(registry)
            register_env_macros(registry)
            register_time_macros(registry)
            register_variable_macros(registry)
            registry
          end

          def self.register_core_macros(registry)
            registry.register("newline") do |inv|
              count = Integer(Array(inv.args).first.to_s.strip)
              count = 1 if count <= 0
              "\n" * count
            rescue StandardError
              "\n"
            end
            registry.register("noop") { "" }

            registry.register("trim") do |inv|
              content = Array(inv.args).first
              # Scoped trim returns its content (the engine trims by default).
              return content.to_s if content

              # Non-scoped trim returns a marker, removed by post-processing.
              "{{trim}}"
            end

            registry.register("outlet") do |inv|
              key = Array(inv.args).first.to_s.strip
              next "" if key.empty?

              outlets = inv.outlets
              outlets.is_a?(Hash) ? (outlets[key] || outlets[key.to_s] || "") : ""
            end

            registry.register("random") do |inv|
              list = extract_list(inv)
              next "" if list.empty?

              list[inv.rng_or_new.rand(list.length)].to_s
            end

            registry.register("pick") do |inv|
              list = extract_list(inv)
              next "" if list.empty?

              list[inv.pick_index(list.length)].to_s
            end
          end

          def self.register_env_macros(registry)
            registry.register("user") { |inv| inv.environment.user_name.to_s }
            registry.register("char") { |inv| inv.environment.character_name.to_s }

            registry.register("group") { |inv| inv.environment.group_name.to_s }
            registry.register_alias("group", "charIfNotGroup", visible: false)

            registry.register("persona") do |inv|
              user = inv.environment.respond_to?(:user) ? inv.environment.user : nil
              user.respond_to?(:persona_text) ? user.persona_text.to_s : ""
            end

            registry.register("charDescription") do |inv|
              char = inv.environment.respond_to?(:character) ? inv.environment.character : nil
              char.respond_to?(:data) ? char.data.description.to_s : ""
            end
            registry.register_alias("charDescription", "description")

            registry.register("charPersonality") do |inv|
              char = inv.environment.respond_to?(:character) ? inv.environment.character : nil
              char.respond_to?(:data) ? char.data.personality.to_s : ""
            end
            registry.register_alias("charPersonality", "personality")

            registry.register("charScenario") do |inv|
              char = inv.environment.respond_to?(:character) ? inv.environment.character : nil
              char.respond_to?(:data) ? char.data.scenario.to_s : ""
            end
            registry.register_alias("charScenario", "scenario")

            registry.register("mesExamplesRaw") do |inv|
              char = inv.environment.respond_to?(:character) ? inv.environment.character : nil
              char.respond_to?(:data) ? char.data.mes_example.to_s : ""
            end
          end

          def self.register_time_macros(registry)
            # {{time}} or {{time::UTC+2}}
            registry.register("time") do |inv|
              raw = Array(inv.args).first
              return inv.now.strftime("%-I:%M %p") if raw.nil? || raw.to_s.strip.empty?

              match = raw.to_s.strip.match(/\AUTC(?<hours>[+-]\d+)\z/i)
              return inv.now.strftime("%-I:%M %p") unless match

              offset_hours = Integer(match[:hours])
              inv.now.utc.getlocal(offset_hours * 3600).strftime("%-I:%M %p")
            rescue StandardError
              ""
            end
          end

          def self.register_variable_macros(registry)
            registry.register("setvar") do |inv|
              name, value = Array(inv.args)
              key = name.to_s.strip
              inv.environment.set_var(key, value.to_s, scope: :local) if !key.empty? && inv.environment.respond_to?(:set_var)
              ""
            end

            registry.register("getvar") do |inv|
              name = Array(inv.args).first.to_s.strip
              v = inv.environment.respond_to?(:get_var) ? inv.environment.get_var(name, scope: :local) : nil
              normalize(v)
            end

            registry.register("hasvar") do |inv|
              name = Array(inv.args).first.to_s.strip
              has = inv.environment.respond_to?(:has_var?) ? inv.environment.has_var?(name, scope: :local) : false
              has ? "true" : "false"
            end
            registry.register_alias("hasvar", "varexists")

            registry.register("deletevar") do |inv|
              name = Array(inv.args).first.to_s.strip
              inv.environment.delete_var(name, scope: :local) if inv.environment.respond_to?(:delete_var)
              ""
            end
            registry.register_alias("deletevar", "flushvar")

            registry.register("setglobalvar") do |inv|
              name, value = Array(inv.args)
              key = name.to_s.strip
              inv.environment.set_var(key, value.to_s, scope: :global) if !key.empty? && inv.environment.respond_to?(:set_var)
              ""
            end

            registry.register("getglobalvar") do |inv|
              name = Array(inv.args).first.to_s.strip
              v = inv.environment.respond_to?(:get_var) ? inv.environment.get_var(name, scope: :global) : nil
              normalize(v)
            end

            registry.register("hasglobalvar") do |inv|
              name = Array(inv.args).first.to_s.strip
              has = inv.environment.respond_to?(:has_var?) ? inv.environment.has_var?(name, scope: :global) : false
              has ? "true" : "false"
            end
            registry.register_alias("hasglobalvar", "globalvarexists")

            registry.register("deleteglobalvar") do |inv|
              name = Array(inv.args).first.to_s.strip
              inv.environment.delete_var(name, scope: :global) if inv.environment.respond_to?(:delete_var)
              ""
            end
            registry.register_alias("deleteglobalvar", "flushglobalvar")
          end

          def self.extract_hours_offset(inv)
            raw =
              if inv.args.is_a?(Array)
                inv.args.first
              else
                inv.args
              end

            Integer(raw.to_s.strip)
          rescue StandardError
            0
          end

          def self.extract_list(inv)
            args = Array(inv.args).map(&:to_s)
            return [] if args.empty?

            if args.length == 1
              inv.split_list(args.first)
            else
              args
            end
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

          private_class_method :register_core_macros, :register_env_macros, :register_time_macros,
            :register_variable_macros, :extract_hours_offset, :extract_list, :normalize
        end
      end
    end
  end
end
