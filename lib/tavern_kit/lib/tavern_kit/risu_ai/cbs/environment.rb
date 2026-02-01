# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      class Environment < TavernKit::Macro::Environment::Base
        attr_reader :character,
                    :user,
                    :history,
                    :greeting_index,
                    :chat_index,
                    :message_index,
                    :dialect,
                    :model_hint,
                    :role,
                    :rng_word,
                    :modules,
                    :metadata,
                    :cbs_conditions,
                    :displaying,
                    :run_var,
                    :rm_var

        def self.build(**kwargs)
          new(**kwargs)
        end

        def initialize(
          character: nil,
          user: nil,
          history: nil,
          greeting_index: nil,
          chat_index: nil,
          message_index: nil,
          dialect: nil,
          model_hint: nil,
          role: nil,
          rng_word: nil,
          modules: nil,
          metadata: nil,
          cbs_conditions: nil,
          displaying: nil,
          variables: nil,
          toggles: nil,
          run_var: nil,
          rm_var: nil,
          **_kwargs
        )
          @character = character
          @user = user
          @history = history
          @greeting_index = greeting_index.nil? ? nil : greeting_index.to_i
          @chat_index = chat_index
          @message_index = message_index
          @dialect = dialect&.to_sym
          @model_hint = model_hint.to_s
          @role = role
          @rng_word = rng_word.to_s
          @modules = Array(modules).map(&:to_s)
          @metadata = normalize_metadata(metadata)
          @cbs_conditions = normalize_metadata(cbs_conditions)

          @displaying = displaying == true

          @variables = variables
          @toggles = normalize_toggles(toggles)

          @run_var = run_var == true
          @rm_var = rm_var == true

          @temp_vars = {}
          @function_arg_vars = {}
        end

        def character_name = @character&.name.to_s
        def user_name = @user&.name.to_s

        # Lightweight fingerprint for cache keys. This is best-effort and only
        # intended for in-process memoization.
        def cache_fingerprint
          vars = @variables
          vars_id = vars ? vars.object_id : 0
          vars_version = vars.respond_to?(:cache_version) ? vars.cache_version : nil

          [
            character_name,
            user_name,
            @greeting_index,
            @chat_index,
            @message_index,
            @dialect,
            @model_hint,
            @role.to_s,
            @rng_word,
            @modules,
            @metadata,
            @cbs_conditions,
            @toggles,
            @displaying,
            @run_var,
            @rm_var,
            vars_id,
            vars_version,
          ].hash
        end

        # Start a fresh CBS evaluation frame.
        #
        # Upstream behavior: functions persist across nested call:: expansions,
        # but temp variables reset for each parse frame.
        def call_frame(**overrides)
          self.class.build(
            character: @character,
            user: @user,
            history: @history,
            greeting_index: @greeting_index,
            chat_index: @chat_index,
            message_index: @message_index,
            dialect: @dialect,
            model_hint: @model_hint,
            role: @role,
            rng_word: @rng_word,
            modules: @modules,
            metadata: @metadata,
            cbs_conditions: @cbs_conditions,
            displaying: @displaying,
            variables: @variables,
            toggles: @toggles,
            run_var: @run_var,
            rm_var: @rm_var,
            **overrides,
          )
        end

        def get_var(name, scope: :local)
          scope = normalize_scope(scope)
          key = name.to_s

          if scope == :global && key.start_with?("toggle_")
            toggle_name = key.delete_prefix("toggle_")
            value = @toggles[toggle_name] || @toggles[key]
            return "null" if value.nil?
            return value.to_s
          end

          case scope
          when :local, :global
            return "null" unless @variables&.respond_to?(:get)

            value = @variables.get(key, scope: scope)
            return "null" if value.nil?
            value.to_s
          when :temp
            @temp_vars[key] || ""
          when :function_arg
            @function_arg_vars[key] || ""
          else
            nil
          end
        end

        def set_var(name, value, scope: :local)
          scope = normalize_scope(scope)
          key = name.to_s

          case scope
          when :local, :global
            return nil unless @variables

            if @variables.respond_to?(:set)
              @variables.set(key, value, scope: scope)
            end
          when :temp
            @temp_vars[key] = value
          when :function_arg
            @function_arg_vars[key] = value
          end
        end

        def has_var?(name, scope: :local)
          scope = normalize_scope(scope)
          key = name.to_s

          if scope == :global && key.start_with?("toggle_")
            toggle_name = key.delete_prefix("toggle_")
            return @toggles.key?(toggle_name) || @toggles.key?(key)
          end

          case scope
          when :local, :global
            return false unless @variables

            if @variables.respond_to?(:has?)
              @variables.has?(key, scope: scope)
            else
              false
            end
          when :temp
            @temp_vars.key?(key)
          when :function_arg
            @function_arg_vars.key?(key)
          else
            false
          end
        end

        private

        def normalize_scope(scope)
          scope.to_s.downcase.to_sym
        end

        def normalize_toggles(toggles)
          return {} unless toggles.is_a?(Hash)

          all_string = true
          toggles.each_key do |key|
            next if key.is_a?(String)

            all_string = false
            break
          end
          return toggles if all_string

          toggles.each_with_object({}) do |(k, v), out|
            out[k.to_s] = v
          end
        end

        def normalize_metadata(metadata)
          return {} unless metadata.is_a?(Hash)

          metadata.each_with_object({}) do |(k, v), out|
            # Match CBS macro normalization: lowercased and stripped of separators.
            key = k.to_s.downcase.gsub(/[\s_-]+/, "")
            out[key] = v
          end
        end
      end
    end
  end
end
