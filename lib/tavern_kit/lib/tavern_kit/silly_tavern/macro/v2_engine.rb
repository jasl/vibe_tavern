# frozen_string_literal: true

require_relative "invocation"
require_relative "preprocessors"
require_relative "packs/silly_tavern"

module TavernKit
  module SillyTavern
    module Macro
      # Parser-based SillyTavern macro engine (Wave 3).
      #
      # This is a Ruby re-implementation of ST's v2 macro pipeline:
      # - priority-ordered pre/post processors (see Preprocessors)
      # - nested macro evaluation in arguments and scoped content
      # - scoped macro pairing: {{macro}}...{{/macro}}
      # - variable shorthand expressions (e.g. {{.var+=1}})
      #
      # Design note: we intentionally implement "best-effort" parsing to remain
      # tolerant of user-provided prompt strings.
      class V2Engine < TavernKit::Macro::Engine::Base
        UNKNOWN_POLICIES = %i[keep empty].freeze
        VAR_NAME_PATTERN = /[a-zA-Z](?:[\w-]*[\w])?/.freeze
        VAR_EXPR_PATTERN =
          /\A(?<scope>[.$])(?<name>#{VAR_NAME_PATTERN})\s*(?<op>\+\+|--|\|\|=|\?\?=|\+=|-=|\|\||\?\?|==|!=|>=|<=|>|<|=)?(?<value>.*)\z/m.freeze

        def initialize(registry: Packs::SillyTavern.default_registry, unknown: :keep)
          unless UNKNOWN_POLICIES.include?(unknown)
            raise ArgumentError, "unknown must be one of: #{UNKNOWN_POLICIES.inspect}"
          end

          @registry = registry
          @unknown = unknown
        end

        def expand(text, environment:)
          return "" if text.nil?

          str = text.to_s
          return str if str.empty?

          preprocessed = Preprocessors.preprocess(str, environment: environment)
          raw_content_hash = Invocation.stable_hash(preprocessed)
          original_once = build_original_once(environment)

          out = evaluate_content(
            preprocessed,
            environment,
            raw_content_hash: raw_content_hash,
            original_once: original_once,
            context_offset: 0,
          )

          out = Preprocessors.postprocess(out, environment: environment)
          out = remove_unresolved_placeholders(out) if @unknown == :empty
          out
        end

        private

        ArgSpan = Data.define(:raw, :start_offset, :end_offset)

        def evaluate_content(text, env, raw_content_hash:, original_once:, context_offset:)
          out = +""
          i = 0
          str = text.to_s

          while i < str.length
            open = str.index("{{", i)
            if open.nil?
              out << str[i..].to_s
              break
            end

            out << str[i...open] if open > i

            close = find_macro_close(str, open)
            if close.nil?
              out << str[open..].to_s
              break
            end

            raw_inner = str[(open + 2)...close].to_s
            raw_original = str[open...(close + 2)].to_s

            value =
              evaluate_macro(
                str,
                open: open,
                close: close,
                raw_inner: raw_inner,
                raw_original: raw_original,
                env: env,
                raw_content_hash: raw_content_hash,
                original_once: original_once,
                context_offset: context_offset,
              )

            out << value[:output]
            i = value[:next_index]
          end

          out
        end

        def evaluate_macro(str, open:, close:, raw_inner:, raw_original:, env:, raw_content_hash:, original_once:, context_offset:)
          inner_start = open + 2
          global_offset = context_offset + open

          variable = evaluate_variable_expr(
            raw_inner,
            env,
            raw_content_hash: raw_content_hash,
            original_once: original_once,
            context_offset: context_offset,
            open: open,
          )
          return { output: variable, next_index: close + 2 } if variable

          info = parse_macro_inner(raw_inner)
          return { output: raw_original, next_index: close + 2 } if info.nil?

          key = info[:key]
          name = info[:name]
          flags = info[:flags]
          arg_spans = info[:args]

          if flags.closing_block?
            return { output: raw_original, next_index: close + 2 }
          end

          # Dynamic macros: only match argless, non-scoped `{{name}}`.
          if arg_spans.empty? && env.respond_to?(:dynamic_macros)
            dyn = env.dynamic_macros
            if dyn.is_a?(Hash)
              dyn_value = lookup_dynamic(dyn, key)
              if dyn_value
                value = dyn_value.respond_to?(:call) ? dyn_value.call : dyn_value
                return { output: normalize_value(value), next_index: close + 2 }
              end
            end
          end

          defn = @registry.respond_to?(:get) ? @registry.get(key) : nil
          can_scope = defn.nil? ? true : defn.accepts_scoped_content?(arg_spans.length)

          if can_scope
            closing = find_matching_closing(str, close + 2, key)
            if closing
              if defn.nil?
                raw = str[open...(closing[:close] + 2)].to_s
                return { output: (@unknown == :empty ? "" : raw), next_index: closing[:close] + 2 }
              end

              scoped_start = close + 2
              scoped_end = closing[:open] - 1
              raw_scoped = scoped_start > scoped_end ? "" : str[scoped_start..scoped_end].to_s
              raw_block = str[open...(closing[:close] + 2)].to_s

              output =
                evaluate_invocation(
                  defn,
                  name,
                  key,
                  raw_inner,
                  flags,
                  arg_spans,
                  raw_scoped,
                  raw_original,
                  env,
                  raw_content_hash: raw_content_hash,
                  original_once: original_once,
                  context_offset: context_offset,
                  inner_start: inner_start,
                  global_offset: global_offset,
                  open: open,
                  close: close,
                  scoped_start: scoped_start,
                  scoped: true,
                  fallback: raw_block,
                )

              return { output: output, next_index: closing[:close] + 2 }
            end
          end

          if defn.nil?
            # Unknown macro: best-effort tolerance.
            return { output: (@unknown == :empty ? "" : raw_original), next_index: close + 2 }
          end

          output =
            evaluate_invocation(
              defn,
              name,
              key,
              raw_inner,
              flags,
              arg_spans,
              nil,
              raw_original,
              env,
              raw_content_hash: raw_content_hash,
              original_once: original_once,
              context_offset: context_offset,
              inner_start: inner_start,
              global_offset: global_offset,
              open: open,
              close: close,
              scoped_start: nil,
              scoped: false,
              fallback: raw_original,
            )

          { output: output, next_index: close + 2 }
        end

        def evaluate_invocation(
          defn,
          name,
          key,
          raw_inner,
          flags,
          arg_spans,
          raw_scoped,
          raw_original,
          env,
          raw_content_hash:,
          original_once:,
          context_offset:,
          inner_start:,
          global_offset:,
          open:,
          close:,
          scoped_start:,
          scoped:,
          fallback:
        )
          delay = defn.respond_to?(:delay_arg_resolution?) && defn.delay_arg_resolution?

          args = []
          raw_args = []

          arg_spans.each do |span|
            raw = span.raw.to_s
            raw_args << raw

            if delay
              args << raw.strip
            else
              arg_offset = context_offset + inner_start + span.start_offset.to_i
              args << evaluate_content(raw, env, raw_content_hash: raw_content_hash, original_once: original_once, context_offset: arg_offset)
            end
          end

          if scoped
            raw_scoped_text = raw_scoped.to_s
            raw_args << raw_scoped_text

            if delay
              args << raw_scoped_text
            else
              scoped_value =
                evaluate_content(
                  raw_scoped_text,
                  env,
                  raw_content_hash: raw_content_hash,
                  original_once: original_once,
                  context_offset: context_offset + scoped_start.to_i,
                )

              scoped_value = trim_scoped_content(scoped_value) unless flags.preserve_whitespace?
              args << scoped_value
            end
          end

          validate_invocation_arity!(defn, args, env: env)
          validate_invocation_arg_types!(defn, args, env: env)

          if key == "original"
            return original_once ? original_once.call : ""
          end

          resolver = lambda do |text, offset_delta: 0|
            evaluate_content(
              text.to_s,
              env,
              raw_content_hash: raw_content_hash,
              original_once: original_once,
              context_offset: global_offset + offset_delta.to_i,
            )
          end

          trimmer = lambda do |content, trim_indent: true|
            trim_scoped_content(content, trim_indent: trim_indent == true)
          end

          warner = lambda do |message|
            env.warn(message) if env.respond_to?(:warn)
          end

          inv = Invocation.new(
            raw_inner: raw_inner.to_s.strip,
            key: key,
            name: key.to_sym,
            args: args,
            raw_args: raw_args,
            flags: flags,
            is_scoped: scoped == true,
            range: { start_offset: open, end_offset: close + 1 },
            offset: global_offset,
            raw_content_hash: raw_content_hash,
            environment: env,
            resolver: resolver,
            trimmer: trimmer,
            warner: warner,
          )

          handler = defn.handler
          value =
            if handler.is_a?(Proc) && handler.arity == 0
              handler.call
            else
              handler.call(inv)
            end

          post_process(env, value, fallback: fallback)
        rescue TavernKit::SillyTavern::MacroError => e
          env.warn(e.message) if env.respond_to?(:warn)
          fallback.to_s
        end

        def find_matching_closing(text, start_idx, target_key)
          depth = 1
          i = start_idx.to_i
          str = text.to_s

          while i < str.length
            open = str.index("{{", i)
            return nil if open.nil?

            close = find_macro_close(str, open)
            return nil if close.nil?

            inner = str[(open + 2)...close].to_s
            info = parse_macro_inner(inner)
            if info
              key = info[:key]
              if key == target_key
                if info[:flags].closing_block?
                  depth -= 1
                  return { open: open, close: close } if depth.zero?
                else
                  defn = @registry.respond_to?(:get) ? @registry.get(key) : nil
                  depth += 1 if defn.nil? || defn.accepts_scoped_content?(info[:args].length)
                end
              end
            end

            i = close + 2
          end

          nil
        end

        # Find the closing "}}" for a macro starting at `open` (the index of "{{"),
        # supporting nested macros like `{{outer::{{inner}}}}`.
        def find_macro_close(text, open)
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

        def parse_macro_inner(raw_inner)
          s = raw_inner.to_s
          len = s.length
          i = 0

          i += 1 while i < len && whitespace?(s.getbyte(i))
          return nil if i >= len

          # Special-case comment closing tag: {{///}}.
          if s.getbyte(i) == "/".ord && s[i, 3] == "///"
            rest = s[(i + 3)..].to_s
            if rest.strip.empty?
              return {
                name: "//",
                key: "//",
                flags: Flags.parse(["/"]),
                args: [],
              }
            end
          end

          # Special-case comment macro identifier: {{// ...}}.
          if s[i, 2] == "//"
            name = "//"
            key = "//"
            args, = parse_args(s, i + 2)
            return { name: name, key: key, flags: Flags.empty, args: args }
          end

          flags_symbols = []
          loop do
            i += 1 while i < len && whitespace?(s.getbyte(i))
            break if i >= len

            ch = s.getbyte(i)
            break unless flag_byte?(ch)

            flags_symbols << ch.chr
            i += 1
          end

          flags = Flags.parse(flags_symbols)

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

          args, = parse_args(s, i)
          { name: name, key: name.downcase, flags: flags, args: args }
        end

        def parse_args(raw_inner, start_idx)
          s = raw_inner.to_s
          len = s.length
          i = start_idx.to_i

          i += 1 while i < len && whitespace?(s.getbyte(i))
          if s.getbyte(i) == ":".ord
            i += s.getbyte(i + 1) == ":".ord ? 2 : 1
          end

          spans = []
          i += 1 while i < len && whitespace?(s.getbyte(i))
          return [spans, i] if i >= len

          depth = 0
          seg_start = i
          cursor = i

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
              spans << build_arg_span(s, seg_start, cursor)
              cursor += 2
              seg_start = cursor
              seg_start += 1 while seg_start < len && whitespace?(s.getbyte(seg_start))
              cursor = seg_start
              next
            end

            cursor += 1
          end

          spans << build_arg_span(s, seg_start, len)
          [spans, len]
        end

        def build_arg_span(str, left, right)
          l = left.to_i
          r = right.to_i

          l += 1 while l < r && whitespace?(str.getbyte(l))
          r -= 1 while r > l && whitespace?(str.getbyte(r - 1))

          ArgSpan.new(raw: str[l...r], start_offset: l, end_offset: r - 1)
        end

        def evaluate_variable_expr(raw_inner, env, raw_content_hash:, original_once:, context_offset:, open:)
          s = raw_inner.to_s
          first_non_ws = s.index(/\S/)
          return nil unless first_non_ws

          expr = s[first_non_ws..].to_s
          return nil unless expr.start_with?(".", "$")

          m = expr.match(VAR_EXPR_PATTERN)
          return nil unless m

          scope = m[:scope] == "$" ? :global : :local
          name = m[:name].to_s
          op = m[:op]
          value_raw = m[:value].to_s

          return nil unless env.respond_to?(:get_var) && env.respond_to?(:set_var) && env.respond_to?(:has_var?)

          value_start_in_inner = first_non_ws + (m.begin(:value) || 0)
          value_context_offset = context_offset + open + 2 + value_start_in_inner

          lazy_value = build_lazy_value(
            env,
            value_raw,
            raw_content_hash: raw_content_hash,
            original_once: original_once,
            context_offset: value_context_offset,
          )

          vars_get = -> { env.get_var(name, scope: scope) }
          vars_set = ->(v) { env.set_var(name, v, scope: scope) }
          vars_has = -> { env.has_var?(name, scope: scope) }

          case op
          when nil
            normalize_value(vars_get.call)
          when "="
            vars_set.call(lazy_value.call)
            ""
          when "++"
            current = coerce_number(vars_get.call) || 0
            next_val = current + 1
            vars_set.call(next_val)
            normalize_value(next_val)
          when "--"
            current = coerce_number(vars_get.call) || 0
            next_val = current - 1
            vars_set.call(next_val)
            normalize_value(next_val)
          when "+="
            apply_var_add(env, name, scope: scope, value: lazy_value.call)
            ""
          when "-="
            apply_var_sub(env, name, scope: scope, value: lazy_value.call)
            ""
          when "||"
            current = vars_get.call
            falsy?(current) ? normalize_value(lazy_value.call) : normalize_value(current)
          when "??"
            vars_has.call ? normalize_value(vars_get.call) : normalize_value(lazy_value.call)
          when "||="
            current = vars_get.call
            if falsy?(current)
              vars_set.call(lazy_value.call)
              normalize_value(lazy_value.call)
            else
              normalize_value(current)
            end
          when "??="
            if !vars_has.call
              vars_set.call(lazy_value.call)
              normalize_value(lazy_value.call)
            else
              normalize_value(vars_get.call)
            end
          when "=="
            normalize_value(vars_get.call) == normalize_value(lazy_value.call) ? "true" : "false"
          when "!="
            normalize_value(vars_get.call) != normalize_value(lazy_value.call) ? "true" : "false"
          when ">", ">=", "<", "<="
            left = coerce_number(vars_get.call)
            right = coerce_number(lazy_value.call)
            if left.nil? || right.nil?
              env.warn(%(Variable shorthand "#{op}" operator requires numeric values.)) if env.respond_to?(:warn)
              "false"
            else
              compare_numbers(op, left, right) ? "true" : "false"
            end
          else
            nil
          end
        rescue StandardError
          nil
        end

        def build_lazy_value(env, raw, raw_content_hash:, original_once:, context_offset:)
          resolved = false
          cached = nil

          lambda do
            unless resolved
              cached =
                evaluate_content(
                  raw.to_s.strip,
                  env,
                  raw_content_hash: raw_content_hash,
                  original_once: original_once,
                  context_offset: context_offset.to_i,
                ).strip
              resolved = true
            end
            cached
          end
        end

        def compare_numbers(op, left, right)
          case op
          when ">" then left > right
          when ">=" then left >= right
          when "<" then left < right
          when "<=" then left <= right
          else false
          end
        end

        def apply_var_add(env, name, scope:, value:)
          current = env.get_var(name, scope: scope)
          rhs_num = coerce_number(value)
          cur_num = coerce_number(current)

          if !rhs_num.nil? && (current.nil? || !cur_num.nil?)
            env.set_var(name, (cur_num || 0) + rhs_num, scope: scope)
          else
            env.set_var(name, "#{current}#{value}", scope: scope)
          end
        end

        def apply_var_sub(env, name, scope:, value:)
          current = env.get_var(name, scope: scope)
          rhs_num = coerce_number(value)
          cur_num = coerce_number(current)

          if rhs_num.nil? || cur_num.nil?
            env.warn(%(Variable shorthand "-=" operator requires a numeric value.)) if env.respond_to?(:warn)
            return
          end

          env.set_var(name, cur_num - rhs_num, scope: scope)
        end

        def coerce_number(value)
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

        def falsy?(value)
          s = normalize_value(value).strip.downcase
          s.empty? || %w[off false 0].include?(s)
        end

        def post_process(env, value, fallback:)
          if env.respond_to?(:post_process)
            env.post_process.call(value)
          else
            value.to_s
          end
        rescue StandardError
          fallback.to_s
        end

        def validate_invocation_arity!(defn, args, env:)
          count = Array(args).length
          return if defn.arity_valid?(count)

          list = defn.list_spec
          expected_min = list ? defn.min_args + list.fetch(:min, 0).to_i : defn.min_args
          expected_max =
            if list
              max = list[:max]
              max.nil? ? nil : defn.max_args + max.to_i
            else
              defn.max_args
            end

          expectation =
            if !expected_max.nil? && expected_max != expected_min
              "between #{expected_min} and #{expected_max}"
            elsif !expected_max.nil?
              expected_min.to_s
            else
              "at least #{expected_min}"
            end

          message = %(Macro "#{defn.name}" called with #{count} unnamed arguments but expects #{expectation}.)
          raise TavernKit::SillyTavern::MacroSyntaxError.new(message, macro_name: defn.name) if defn.strict_args?

          env.warn(message) if env.respond_to?(:warn)
        end

        def validate_invocation_arg_types!(defn, args, env:)
          defs = defn.unnamed_arg_defs
          return if defs.empty?

          all_args = Array(args)
          unnamed_count = [all_args.length, defn.max_args].min
          unnamed = all_args.first(unnamed_count)
          return if unnamed.empty?

          count = [defs.length, unnamed.length].min
          count.times do |idx|
            arg_def = defs[idx]
            value = unnamed[idx].to_s

            raw_type =
              if arg_def.is_a?(Hash)
                arg_def[:type] || arg_def["type"] || :string
              else
                :string
              end

            types = Array(raw_type).map { |t| normalize_value_type(t) }.uniq
            next if types.any? { |t| value_of_type?(value, t) }

            arg_name =
              if arg_def.is_a?(Hash)
                arg_def[:name] || arg_def["name"] || "Argument #{idx + 1}"
              else
                "Argument #{idx + 1}"
              end

            optional =
              if arg_def.is_a?(Hash)
                arg_def[:optional] || arg_def["optional"]
              else
                false
              end

            optional_label = optional ? " (optional)" : ""
            message =
              %(Macro "#{defn.name}" (position #{idx + 1}#{optional_label}) argument "#{arg_name}" expected type #{raw_type} but got value "#{value}".)

            raise TavernKit::SillyTavern::MacroSyntaxError.new(message, macro_name: defn.name, position: idx + 1) if defn.strict_args?

            env.warn(message) if env.respond_to?(:warn)
          end
        end

        # Helper methods extracted to `silly_tavern/macro/v2_engine/helpers.rb` (Wave 6 large-file split).
      end
    end
  end
end

require_relative "v2_engine/helpers"
