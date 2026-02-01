# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      # Internal evaluator methods for `V2Engine`.
      #
      # Pure refactor: extracted from `silly_tavern/macro/v2_engine.rb` (Wave 6 large-file split).
      class V2Engine < TavernKit::Macro::Engine::Base
        private

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
      end
    end
  end
end
