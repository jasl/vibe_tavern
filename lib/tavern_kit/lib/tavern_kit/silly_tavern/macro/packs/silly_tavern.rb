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
            registry.register(
              "space",
              unnamed_args: [
                { name: "count", optional: true, type: :integer },
              ],
            ) do |inv|
              count = Integer(Array(inv.args).first.to_s.strip)
              count = 1 if count <= 0
              " " * count
            rescue StandardError
              " "
            end

            registry.register(
              "newline",
              unnamed_args: [
                { name: "count", optional: true, type: :integer },
              ],
            ) do |inv|
              count = Integer(Array(inv.args).first.to_s.strip)
              count = 1 if count <= 0
              "\n" * count
            rescue StandardError
              "\n"
            end
            registry.register("noop") { "" }

            registry.register(
              "trim",
              unnamed_args: [
                { name: "content", optional: true, type: :string },
              ],
            ) do |inv|
              content = Array(inv.args).first
              # Scoped trim returns its content (the engine trims by default).
              return content.to_s if content

              # Non-scoped trim returns a marker, removed by post-processing.
              "{{trim}}"
            end

            registry.register(
              "if",
              unnamed_args: [
                { name: "condition", type: :string },
                { name: "content", type: :string },
              ],
              delay_arg_resolution: true,
            ) do |inv|
              raw_condition, raw_content = Array(inv.args)

              inverted = false
              condition = raw_condition.to_s
              if condition.match?(/\A\s*!/)
                inverted = true
                condition = condition.sub(/\A\s*!\s*/, "")
              end

              condition = inv.resolve(condition).to_s

              # Variable shorthand lookup in conditions (.var / $var).
              if condition.match?(/\A[.$]#{TavernKit::SillyTavern::Macro::V2Engine::VAR_NAME_PATTERN}\z/)
                prefix = condition[0]
                var_name = condition[1..].to_s
                scope = prefix == "$" ? :global : :local
                condition = inv.environment.get_var(var_name, scope: scope).to_s if inv.environment.respond_to?(:get_var)
              else
                # Auto-resolve bare macro names (best-effort): description -> {{description}}.
                candidate = condition.strip
                if candidate.match?(/\A[a-zA-Z][\w-]*\z/) && !candidate.include?("{{") && !candidate.include?("}}")
                  resolved = inv.resolve("{{#{candidate}}}")
                  condition = resolved unless resolved.casecmp("{{#{candidate}}}").zero?
                end
              end

              falsy = condition.to_s.strip.empty? || %w[off false 0].include?(condition.to_s.strip.downcase)
              falsy = !falsy if inverted

              branches = split_on_top_level_else(raw_content.to_s)
              chosen = falsy ? branches[:else] : branches[:then]
              return "" if chosen.nil?

              rendered = inv.resolve(chosen)
              inv.flags.preserve_whitespace? ? rendered : inv.trim_content(rendered)
            end

            registry.register("else") { Preprocessors::ELSE_MARKER }

            registry.register(
              "//",
              unnamed_args: [
                { name: "comment", type: :string },
              ],
              list: true,
              strict_args: false,
            ) { "" }
            registry.register_alias("//", "comment", visible: false)

            registry.register(
              "outlet",
              unnamed_args: [
                { name: "key", type: :string },
              ],
            ) do |inv|
              key = Array(inv.args).first.to_s.strip
              next "" if key.empty?

              outlets = inv.outlets
              outlets.is_a?(Hash) ? (outlets[key] || outlets[key.to_s] || "") : ""
            end

            registry.register("random", list: true) do |inv|
              list = extract_list(inv)
              next "" if list.empty?

              list[inv.rng_or_new.rand(list.length)].to_s
            end

            registry.register("pick", list: true) do |inv|
              list = extract_list(inv)
              next "" if list.empty?

              list[inv.pick_index(list.length)].to_s
            end
          end

          def self.register_env_macros(registry)
            # Note: ST's {{original}} expands at most once per evaluation.
            # The V2 engine enforces this at the engine level.
            registry.register("original") do |inv|
              inv.environment.respond_to?(:original) ? inv.environment.original.to_s : ""
            end

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
            registry.register(
              "time",
              unnamed_args: [
                { name: "offset", optional: true, type: :string },
              ],
            ) do |inv|
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

          def self.split_on_top_level_else(content)
            str = content.to_s
            depth = 0
            i = 0

            while i < str.length
              open = str.index("{{", i)
              break if open.nil?

              close = str.index("}}", open + 2)
              break if close.nil?

              inner = str[(open + 2)...close].to_s
              info = extract_macro_info(inner)

              if info
                if info[:key] == "if"
                  if info[:closing]
                    depth -= 1 if depth.positive?
                  elsif info[:arg_count] == 1
                    depth += 1
                  end
                elsif info[:key] == "else" && depth.zero?
                  then_branch = str[0...open]
                  else_branch = str[(close + 2)..]
                  return { then: then_branch, else: else_branch }
                end
              end

              i = close + 2
            end

            { then: str, else: nil }
          end

          def self.extract_macro_info(raw_inner)
            s = raw_inner.to_s
            idx = s.index(/\S/)
            return nil unless idx

            rest = s[idx..].to_s
            return nil if rest.start_with?(".", "$")

            closing = false
            loop do
              rest = rest.lstrip
              break if rest.empty?

              ch = rest[0]
              break unless %w[! ? ~ > # /].include?(ch)

              closing = true if ch == "/"
              rest = rest[1..].to_s
            end

            rest = rest.lstrip
            name, tail = rest.split(/\s+/, 2)
            name = name.to_s
            return nil if name.empty?

            args_part = tail.to_s
            args_part = args_part.delete_prefix("::") if args_part.lstrip.start_with?("::")
            arg_count =
              if args_part.include?("::")
                args_part.split("::", -1).length
              elsif args_part.strip.empty?
                0
              else
                1
              end

            { key: name.downcase, closing: closing, arg_count: arg_count }
          rescue StandardError
            nil
          end

          private_class_method :split_on_top_level_else, :extract_macro_info
        end
      end
    end
  end
end
