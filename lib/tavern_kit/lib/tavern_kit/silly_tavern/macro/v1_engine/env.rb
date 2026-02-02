# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      class V1Engine < TavernKit::Macro::Engine::Base
        private

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
                resolver: nil,
                trimmer: nil,
                warner: nil,
              )

              replaced = evaluate_value(value, inv)
              post_process(env, replaced, fallback: match)
            end
          end

          out
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
      end
    end
  end
end
