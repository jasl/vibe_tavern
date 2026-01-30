# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      module Packs
        module SillyTavern
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

          def self.extract_list(inv)
            args = Array(inv.args).map(&:to_s)
            return [] if args.empty?

            if args.length == 1
              inv.split_list(args.first)
            else
              args
            end
          end

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

          private_class_method :register_core_macros, :extract_list, :split_on_top_level_else, :extract_macro_info
        end
      end
    end
  end
end
