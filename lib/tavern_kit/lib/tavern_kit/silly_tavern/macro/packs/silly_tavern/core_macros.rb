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

            registry.register("input") do |inv|
              attrs = inv.environment.respond_to?(:platform_attrs) ? inv.environment.platform_attrs : {}
              TavernKit::Utils::HashAccessor.wrap(attrs).fetch(:input, default: "")
            end

            registry.register("maxPrompt") do |inv|
              attrs = inv.environment.respond_to?(:platform_attrs) ? inv.environment.platform_attrs : {}
              max = TavernKit::Utils::HashAccessor.wrap(attrs).fetch(:max_prompt, :maxPrompt, :max_context, default: nil)
              max.nil? ? "" : max.to_i.to_s
            end

            registry.register(
              "reverse",
              unnamed_args: [
                { name: "value", type: :string },
              ],
            ) do |inv|
              Array(inv.args).first.to_s.each_char.to_a.reverse.join
            end

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
              "roll",
              unnamed_args: [
                { name: "formula", type: :string },
              ],
            ) do |inv|
              formula = Array(inv.args).first.to_s.strip
              return "" if formula.empty?

              formula = "1d#{formula}" if formula.match?(/\A\d+\z/)

              m = formula.match(/\A(\d+)?d(\d+)([+-]\d+)?\z/i)
              unless m
                inv.warn("Invalid roll formula: #{formula}")
                return ""
              end

              count = (m[1].to_s.empty? ? 1 : m[1].to_i)
              sides = m[2].to_i
              mod = m[3].to_i

              count = [[count, 1].max, 1_000].min
              sides = [[sides, 1].max, 1_000_000].min

              rng = inv.rng_or_new
              total = 0
              count.times { total += rng.rand(1..sides) }
              total += mod

              total.to_s
            end

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

            registry.register(
              "banned",
              unnamed_args: [
                { name: "word", type: :string },
              ],
            ) do |inv|
              raw = Array(inv.args).first.to_s.strip
              word = raw.gsub(/\A"|"\z/, "")
              next "" if word.empty?

              env = inv.environment
              attrs = env.respond_to?(:platform_attrs) ? env.platform_attrs : {}
              main_api = TavernKit::Utils::HashAccessor.wrap(attrs).fetch(:main_api, :mainApi, default: "").to_s
              next "" unless main_api == "textgenerationwebui"

              list = attrs["banned_words"] || attrs["bannedWords"] || attrs[:banned_words] || attrs[:bannedWords]
              list << word if list.is_a?(Array)

              ""
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

              close = find_macro_close(str, open)
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
            len = s.length
            i = 0

            i += 1 while i < len && whitespace?(s.getbyte(i))
            return nil if i >= len

            # Ignore variable shorthand (.var / $var).
            return nil if s[i] == "." || s[i] == "$"

            closing = false
            loop do
              i += 1 while i < len && whitespace?(s.getbyte(i))
              break if i >= len

              ch = s.getbyte(i)
              break unless flag_byte?(ch)

              closing = true if ch == "/".ord
              i += 1
            end

            i += 1 while i < len && whitespace?(s.getbyte(i))
            return nil if i >= len

            name_start = i
            while i < len
              break if whitespace?(s.getbyte(i))
              break if s.getbyte(i) == ":".ord

              i += 1
            end

            name = s[name_start...i].to_s.strip
            return nil if name.empty?

            j = i
            j += 1 while j < len && whitespace?(s.getbyte(j))
            if j < len && s.getbyte(j) == ":".ord
              j += s.getbyte(j + 1) == ":".ord ? 2 : 1
            end
            j += 1 while j < len && whitespace?(s.getbyte(j))

            arg_count =
              if j >= len
                0
              else
                count = 1
                depth = 0
                cursor = j

                while cursor < len
                  if s[cursor, 2] == "{{"
                    depth += 1
                    cursor += 2
                    next
                  end

                  if s[cursor, 2] == "}}"
                    depth -= 1 if depth.positive?
                    cursor += 2
                    next
                  end

                  if depth.zero? && s[cursor, 2] == "::"
                    count += 1
                    cursor += 2
                    next
                  end

                  cursor += 1
                end

                count
              end

            { key: name.downcase, closing: closing, arg_count: arg_count }
          rescue StandardError
            nil
          end

          def self.find_macro_close(text, open)
            str = text.to_s
            depth = 1
            i = open.to_i + 2

            while i < str.length
              next_open = str.index("{{", i)
              next_close = str.index("}}", i)
              return nil if next_open.nil? && next_close.nil?

              if next_close.nil? || (!next_open.nil? && next_open < next_close)
                depth += 1
                i = next_open + 2
              else
                depth -= 1
                return next_close if depth.zero?

                i = next_close + 2
              end
            end

            nil
          end

          def self.whitespace?(byte)
            byte == 32 || byte == 9 || byte == 10 || byte == 13
          end

          def self.flag_byte?(byte)
            case byte
            when "!".ord, "?".ord, "~".ord, ">".ord, "/".ord, "#".ord then true
            else false
            end
          end

          private_class_method :register_core_macros, :extract_list, :split_on_top_level_else, :extract_macro_info,
            :find_macro_close, :whitespace?, :flag_byte?
        end
      end
    end
  end
end
