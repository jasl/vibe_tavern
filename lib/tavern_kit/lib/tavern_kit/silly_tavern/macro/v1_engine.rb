# frozen_string_literal: true

require "json"

require_relative "invocation"

module TavernKit
  module SillyTavern
    module Macro
      # Legacy SillyTavern-style macro expander (multi-pass regex).
      #
      # Compatibility goals:
      # - Case-insensitive macro names
      # - Multi-pass ordering so env substitutions can feed later macros
      # - Unknown macros are preserved by default (tolerant external input)
      class V1Engine < TavernKit::Macro::Engine::Base
        UNKNOWN_POLICIES = %i[keep empty].freeze

        def initialize(unknown: :keep)
          unless UNKNOWN_POLICIES.include?(unknown)
            raise ArgumentError, "unknown must be one of: #{UNKNOWN_POLICIES.inspect}"
          end
          @unknown = unknown
        end

        def expand(text, environment:)
          return "" if text.nil?

          str = text.to_s
          return str if str.empty?

          raw_content = str.dup
          raw_content_hash = Invocation.stable_hash(raw_content)

          env = environment

          # ST behavior: {{original}} expands at most once per evaluation.
          original_once = build_original_once(env)

          out = str.dup

          out = expand_pre_env(out, env, raw_content_hash)
          out = expand_env(out, env, raw_content_hash, original_once)
          out = expand_post_env(out, env, raw_content_hash)

          out = remove_unresolved_placeholders(out) if @unknown == :empty

          out
        end

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

        def expand_env(str, env, raw_content_hash, original_once)
          out = str.to_s
          return out if out.empty?

          env_map = build_env_map(env, original_once)

          # Env macros are simple {{name}} replacements.
          env_map.each do |name, value|
            next if name.empty?

            pattern = /\{\{#{Regexp.escape(name)}\}\}/i
            out = out.gsub(pattern) do |match|
              offset = Regexp.last_match.begin(0) || 0
              inv = Invocation.new(
                raw_inner: name,
                key: name.downcase,
                name: name.downcase.to_sym,
                args: nil,
                raw_args: [],
                flags: Flags.empty,
                is_scoped: false,
                range: nil,
                offset: offset,
                raw_content_hash: raw_content_hash,
                environment: env,
              )

              replaced = evaluate_value(value, inv)
              post_process(env, replaced, fallback: match)
            end
          end

          out
        end

        def expand_post_env(str, env, raw_content_hash)
          out = str.to_s
          return out if out.empty?

          out = out.gsub(/\{\{reverse:(.+?)\}\}/i) do |match|
            args = Regexp.last_match(1).to_s
            post_process(env, args.reverse, fallback: match)
          end

          # ST comment blocks: {{// ... }} removed.
          out = out.gsub(/\{\{\/\/[\s\S]*?\}\}/m, "")

          out = out.gsub(/\{\{outlet::(.+?)\}\}/i) do |match|
            offset = Regexp.last_match.begin(0) || 0
            key = Regexp.last_match(1).to_s.strip
            inv = Invocation.new(
              raw_inner: "outlet::#{key}",
              key: "outlet",
              name: :outlet,
              args: key,
              raw_args: [key],
              flags: Flags.empty,
              is_scoped: false,
              range: nil,
              offset: offset,
              raw_content_hash: raw_content_hash,
              environment: env,
            )

            value =
              if inv.outlets.is_a?(Hash)
                inv.outlets[key] || inv.outlets[key.to_s] || ""
              else
                ""
              end

            post_process(env, value.to_s, fallback: match)
          end

          out = out.gsub(/\{\{random\s?::?([^}]+)\}\}/i) do |match|
            offset = Regexp.last_match.begin(0) || 0
            list_str = Regexp.last_match(1).to_s
            inv = Invocation.new(
              raw_inner: "random::#{list_str}",
              key: "random",
              name: :random,
              args: list_str,
              raw_args: [list_str],
              flags: Flags.empty,
              is_scoped: false,
              range: nil,
              offset: offset,
              raw_content_hash: raw_content_hash,
              environment: env,
            )

            list = inv.split_list
            picked = list.empty? ? "" : list[inv.rng_or_new.rand(list.length)].to_s

            post_process(env, picked, fallback: match)
          end

          out = out.gsub(/\{\{pick\s?::?([^}]+)\}\}/i) do |match|
            offset = Regexp.last_match.begin(0) || 0
            list_str = Regexp.last_match(1).to_s
            inv = Invocation.new(
              raw_inner: "pick::#{list_str}",
              key: "pick",
              name: :pick,
              args: list_str,
              raw_args: [list_str],
              flags: Flags.empty,
              is_scoped: false,
              range: nil,
              offset: offset,
              raw_content_hash: raw_content_hash,
              environment: env,
            )

            list = inv.split_list
            picked = list.empty? ? "" : list[inv.pick_index(list.length)].to_s

            post_process(env, picked, fallback: match)
          end

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

        def build_env_map(env, original_once)
          map = {}

          # External/dynamic macros.
          dyn = env.respond_to?(:dynamic_macros) ? env.dynamic_macros : {}
          if dyn.is_a?(Hash)
            dyn.each do |k, v|
              key = k.to_s.strip
              next if key.empty?
              next if key.include?("{{") || key.include?("}}")

              map[key] = v
            end
          end

          # Common identity macros.
          map["original"] = original_once if original_once
          map["user"] = ->(_inv = nil) { env.respond_to?(:user_name) ? env.user_name : "" }
          map["char"] = ->(_inv = nil) { env.respond_to?(:character_name) ? env.character_name : "" }

          if env.respond_to?(:user) && env.user
            map["persona"] = ->(_inv = nil) { env.user.respond_to?(:persona_text) ? env.user.persona_text.to_s : "" }
          end

          if env.respond_to?(:character) && env.character
            map["description"] = ->(_inv = nil) { env.character.data.description.to_s }
            map["personality"] = ->(_inv = nil) { env.character.data.personality.to_s }
            map["scenario"] = ->(_inv = nil) { env.character.data.scenario.to_s }
            map["mesExamplesRaw"] = ->(_inv = nil) { env.character.data.mes_example.to_s }
          end

          map
        end

        def build_original_once(env)
          return nil unless env.respond_to?(:original)

          original = env.original
          return nil if original.nil? || original.to_s.empty?

          used = false
          lambda do |_inv = nil|
            return "" if used

            used = true
            original.to_s
          end
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

        def evaluate_value(value, invocation)
          callable =
            if value.is_a?(Proc)
              value
            elsif value.respond_to?(:call)
              value
            end

          result =
            if callable.nil?
              value
            elsif callable.is_a?(Proc) && callable.arity == 0
              callable.call
            else
              callable.call(invocation)
            end

          normalize_value(result)
        rescue StandardError
          ""
        end

        def normalize_value(value)
          case value
          when nil then ""
          when TrueClass then "true"
          when FalseClass then "false"
          when String then value
          when Numeric then value.to_s
          when Hash, Array then JSON.generate(value)
          else value.to_s
          end
        rescue StandardError
          ""
        end

        def post_process(env, value, fallback:)
          fn = env.respond_to?(:post_process) ? env.post_process : nil
          return value.to_s unless fn.respond_to?(:call)

          fn.call(value.to_s).to_s
        rescue StandardError
          fallback.to_s
        end

        def remove_unresolved_placeholders(str)
          s = str.to_s
          return s if s.empty?

          prev = nil
          cur = s
          5.times do
            break if cur == prev

            prev = cur
            cur = cur.gsub(/\{\{[^{}]*\}\}/, "")
          end

          cur
        end
      end
    end
  end
end
