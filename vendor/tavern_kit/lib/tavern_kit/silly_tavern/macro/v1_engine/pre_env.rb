# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      class V1Engine < TavernKit::Macro::Engine::Base
        private

        def expand_pre_env(str, env, raw_content_hash)
          out = str.to_s
          return out if out.empty?

          out = expand_angle_bracket_macros(out, env)
          out = out.gsub(/\{\{newline\}\}/i, "\n")
          out = out.gsub(/(?:\r?\n)*\{\{trim\}\}(?:\r?\n)*/i, "")
          out = out.gsub(/\{\{noop\}\}/i, "")

          out = expand_variable_macros(out, env)
          out = expand_roll_macros(out, env, raw_content_hash)

          out
        end

        def expand_angle_bracket_macros(str, env)
          out = str.to_s
          return out if out.empty?

          user = env.respond_to?(:user_name) ? env.user_name : ""
          char = env.respond_to?(:character_name) ? env.character_name : ""

          out
            .gsub(/<USER>/i, user)
            .gsub(/<BOT>/i, char)
            .gsub(/<CHAR>/i, char)
        end

        def expand_variable_macros(str, env)
          out = str.to_s
          return out if out.empty?

          out = out.gsub(/\{\{setvar::([^:}]+)::([\s\S]*?)\}\}/i) do |_match|
            name = Regexp.last_match(1).to_s.strip
            value = Regexp.last_match(2).to_s
            env.set_var(name, value, scope: :local) if env.respond_to?(:set_var)
            ""
          end

          out = out.gsub(/\{\{setglobalvar::([^:}]+)::([\s\S]*?)\}\}/i) do |_match|
            name = Regexp.last_match(1).to_s.strip
            value = Regexp.last_match(2).to_s
            env.set_var(name, value, scope: :global) if env.respond_to?(:set_var)
            ""
          end

          out = out.gsub(/\{\{getvar::([^}]+)\}\}/i) do |_match|
            name = Regexp.last_match(1).to_s.strip
            v = env.respond_to?(:get_var) ? env.get_var(name, scope: :local) : nil
            normalize_value(v)
          end

          out = out.gsub(/\{\{getglobalvar::([^}]+)\}\}/i) do |_match|
            name = Regexp.last_match(1).to_s.strip
            v = env.respond_to?(:get_var) ? env.get_var(name, scope: :global) : nil
            normalize_value(v)
          end

          out = out.gsub(/\{\{hasvar::([^}]+)\}\}/i) do |_match|
            name = Regexp.last_match(1).to_s.strip
            has = env.respond_to?(:has_var?) ? env.has_var?(name, scope: :local) : false
            has ? "true" : "false"
          end

          out = out.gsub(/\{\{hasglobalvar::([^}]+)\}\}/i) do |_match|
            name = Regexp.last_match(1).to_s.strip
            has = env.respond_to?(:has_var?) ? env.has_var?(name, scope: :global) : false
            has ? "true" : "false"
          end

          out = out.gsub(/\{\{deletevar::([^}]+)\}\}/i) do |_match|
            name = Regexp.last_match(1).to_s.strip
            env.delete_var(name, scope: :local) if env.respond_to?(:delete_var)
            ""
          end

          out = out.gsub(/\{\{deleteglobalvar::([^}]+)\}\}/i) do |_match|
            name = Regexp.last_match(1).to_s.strip
            env.delete_var(name, scope: :global) if env.respond_to?(:delete_var)
            ""
          end

          out = out.gsub(/\{\{addvar::([^:}]+)::([\s\S]*?)\}\}/i) do |_match|
            name = Regexp.last_match(1).to_s.strip
            value = Regexp.last_match(2).to_s
            env.add_var(name, value, scope: :local) if env.respond_to?(:add_var)
            ""
          end

          out = out.gsub(/\{\{addglobalvar::([^:}]+)::([\s\S]*?)\}\}/i) do |_match|
            name = Regexp.last_match(1).to_s.strip
            value = Regexp.last_match(2).to_s
            env.add_var(name, value, scope: :global) if env.respond_to?(:add_var)
            ""
          end

          out = out.gsub(/\{\{incvar::([^}]+)\}\}/i) do |_match|
            name = Regexp.last_match(1).to_s.strip
            increment_var(env, name, scope: :local, delta: 1)
          end

          out = out.gsub(/\{\{decvar::([^}]+)\}\}/i) do |_match|
            name = Regexp.last_match(1).to_s.strip
            increment_var(env, name, scope: :local, delta: -1)
          end

          out = out.gsub(/\{\{incglobalvar::([^}]+)\}\}/i) do |_match|
            name = Regexp.last_match(1).to_s.strip
            increment_var(env, name, scope: :global, delta: 1)
          end

          out = out.gsub(/\{\{decglobalvar::([^}]+)\}\}/i) do |_match|
            name = Regexp.last_match(1).to_s.strip
            increment_var(env, name, scope: :global, delta: -1)
          end

          out = out.gsub(/\{\{var::([^:}]+)(?:::([^}]+))?\}\}/i) do |_match|
            name = Regexp.last_match(1).to_s.strip
            index = Regexp.last_match(2)
            v = env.respond_to?(:get_var) ? env.get_var(name, scope: :local) : nil
            normalize_indexed_value(v, index)
          end

          out
        end

        def increment_var(env, name, scope:, delta:)
          return "" unless env.respond_to?(:get_var) && env.respond_to?(:set_var)

          cur = env.get_var(name, scope: scope)
          n =
            begin
              Float(cur)
            rescue StandardError
              0.0
            end
          next_val = n + delta.to_f
          env.set_var(name, next_val, scope: scope)
          normalize_value(next_val)
        end

        def normalize_indexed_value(value, index)
          return normalize_value(value) if index.nil?

          i = index.to_s.strip
          return normalize_value(value) if i.empty? || !i.match?(/\A-?\d+\z/)

          idx = i.to_i
          if value.is_a?(Array)
            normalize_value(value[idx])
          else
            normalize_value(value)
          end
        end

        def expand_roll_macros(str, env, raw_content_hash)
          out = str.to_s
          return out if out.empty?

          out.gsub(/\{\{roll(?:\s|:)([^}]+)\}\}/i) do |match|
            offset = Regexp.last_match.begin(0) || 0
            formula = Regexp.last_match(1).to_s.strip

            inv = Invocation.new(
              raw_inner: "roll #{formula}",
              key: "roll",
              name: :roll,
              args: formula,
              raw_args: [formula],
              flags: Flags.empty,
              is_scoped: false,
              range: nil,
              offset: offset,
              raw_content_hash: raw_content_hash,
              environment: env,
              resolver: nil,
              trimmer: nil,
              warner: nil,
            )

            rolled = roll_dice(formula, rng: inv.rng_or_new)
            post_process(env, rolled, fallback: match)
          end
        end

        def roll_dice(formula, rng:)
          s = formula.to_s.strip
          return "" if s.empty?

          s = "1d#{s}" if s.match?(/\A\d+\z/)

          m = s.match(/\A(\d+)?d(\d+)([+-]\d+)?\z/i)
          return "" unless m

          count = (m[1].to_s.empty? ? 1 : m[1].to_i)
          sides = m[2].to_i
          mod = m[3].to_i

          count = [[count, 1].max, 1_000].min
          sides = [[sides, 1].max, 1_000_000].min

          total = 0
          count.times { total += rng.rand(1..sides) }
          total += mod

          total.to_s
        rescue StandardError
          ""
        end
      end
    end
  end
end
