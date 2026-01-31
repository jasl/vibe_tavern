# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      class Environment < TavernKit::Macro::Environment::Base
        attr_reader :character, :user, :chat_index, :message_index, :dialect, :model_hint, :role, :rng_word, :run_var, :rm_var

        def self.build(**kwargs)
          new(**kwargs)
        end

        def initialize(
          character: nil,
          user: nil,
          chat_index: nil,
          message_index: nil,
          dialect: nil,
          model_hint: nil,
          role: nil,
          rng_word: nil,
          variables: nil,
          toggles: nil,
          run_var: nil,
          rm_var: nil,
          **_kwargs
        )
          @character = character
          @user = user
          @chat_index = chat_index
          @message_index = message_index
          @dialect = dialect&.to_sym
          @model_hint = model_hint.to_s
          @role = role
          @rng_word = rng_word.to_s

          @variables = variables
          @toggles = toggles.is_a?(Hash) ? toggles : {}

          @run_var = run_var == true
          @rm_var = rm_var == true

          @temp_vars = {}
          @function_arg_vars = {}
        end

        def character_name = @character&.name.to_s
        def user_name = @user&.name.to_s

        # Start a fresh CBS evaluation frame.
        #
        # Upstream behavior: functions persist across nested call:: expansions,
        # but temp variables reset for each parse frame.
        def call_frame(**overrides)
          self.class.build(
            character: @character,
            user: @user,
            chat_index: @chat_index,
            message_index: @message_index,
            dialect: @dialect,
            model_hint: @model_hint,
            role: @role,
            rng_word: @rng_word,
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
            return fetch_hash(@toggles, toggle_name) || fetch_hash(@toggles, key)
          end

          case scope
          when :local, :global
            return nil unless @variables

            if @variables.respond_to?(:get)
              @variables.get(key, scope: scope)
            else
              nil
            end
          when :temp
            @temp_vars[key]
          when :function_arg
            @function_arg_vars[key]
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
            return true if @toggles.key?(toggle_name) || @toggles.key?(key)
            return true if @toggles.key?(toggle_name.to_sym) || @toggles.key?(key.to_sym)
            return false
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

        def fetch_hash(hash, key)
          hash[key] || hash[key.to_s] || hash[key.to_sym]
        end
      end
    end
  end
end
