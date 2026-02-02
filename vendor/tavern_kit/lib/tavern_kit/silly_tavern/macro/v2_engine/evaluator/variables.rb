# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      class V2Engine < TavernKit::Macro::Engine::Base
        private

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
      end
    end
  end
end
