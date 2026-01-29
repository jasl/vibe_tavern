# frozen_string_literal: true

require "time"

module TavernKit
  module SillyTavern
    module Macro
      # Execution environment for SillyTavern macro engines.
      #
      # This is the stable, app-facing input surface for macro expansion:
      # callers provide Character/User + variable storage, and optionally
      # additional dynamic macros via `extensions`.
      class Environment < TavernKit::Macro::Environment::Base
        attr_reader :character, :user, :variables, :outlets, :original, :clock, :rng, :content_hash, :extensions
        attr_reader :post_process, :platform_attrs, :warning_handler, :warnings

        def initialize(
          character: nil,
          user: nil,
          variables: TavernKit::ChatVariables::InMemory.new,
          locals: nil,
          globals: nil,
          outlets: {},
          original: nil,
          clock: nil,
          rng: nil,
          content_hash: nil,
          character_name: nil,
          user_name: nil,
          group_name: nil,
          extensions: {},
          post_process: nil,
          warning_handler: nil,
          strict: false,
          warnings: nil,
          **platform_attrs
        )
          @character = character
          @user = user
          @variables = variables || TavernKit::ChatVariables::InMemory.new
          @outlets = outlets.is_a?(Hash) ? outlets : {}
          @original = original.nil? ? nil : original.to_s
          @character_name = character_name.nil? ? nil : character_name.to_s
          @user_name = user_name.nil? ? nil : user_name.to_s
          @group_name = group_name.nil? ? nil : group_name.to_s

          @clock =
            if clock.nil?
              -> { Time.now }
            elsif clock.respond_to?(:call)
              clock
            else
              -> { clock }
            end

          # If callers want deterministic behavior (tests/debugging), pass a
          # seeded Random. Otherwise leave it nil to match ST's typical "fresh
          # entropy" behavior for random-like macros.
          @rng = rng
          @content_hash = content_hash
          @extensions = extensions.is_a?(Hash) ? TavernKit::Utils.deep_stringify_keys(extensions) : {}
          @platform_attrs = TavernKit::Utils.deep_stringify_keys(platform_attrs.is_a?(Hash) ? platform_attrs : {})

          @warning_handler = warning_handler
          @strict = strict == true
          @warnings = warnings.is_a?(Array) ? warnings : []

          @post_process =
            if post_process.respond_to?(:call)
              post_process
            else
              ->(s) { s.to_s }
            end

          seed_variables(locals: locals, globals: globals)
        end

        def strict? = @strict == true

        def warn(message)
          msg = message.to_s
          warnings << msg

          raise TavernKit::StrictModeError, msg if strict?

          warning_handler.call(msg) if warning_handler.respond_to?(:call)

          nil
        end

        def character_name
          return @character_name if @character_name && !@character_name.empty?

          if character.respond_to?(:display_name)
            character.display_name.to_s
          elsif character.respond_to?(:name)
            character.name.to_s
          else
            ""
          end
        end

        def user_name
          return @user_name if @user_name && !@user_name.empty?

          user.respond_to?(:name) ? user.name.to_s : ""
        end

        def group_name
          return @group_name if @group_name && !@group_name.empty?

          # In ST, `group` often falls back to the bot name for non-group chats.
          character_name
        end

        def now
          value = @clock.call
          value.is_a?(Time) ? value : Time.parse(value.to_s)
        rescue StandardError
          Time.now
        end

        def get_var(name, scope: :local)
          variables.get(name.to_s, scope: scope)
        end

        def set_var(name, value, scope: :local)
          variables.set(name.to_s, value, scope: scope)
        end

        def has_var?(name, scope: :local)
          variables.has?(name.to_s, scope: scope)
        end

        def delete_var(name, scope: :local)
          return nil unless variables.respond_to?(:delete)

          variables.delete(name.to_s, scope: scope)
        end

        def add_var(name, value, scope: :local)
          return nil unless variables.respond_to?(:add)

          variables.add(name.to_s, value, scope: scope)
        end

        def dynamic_macros = extensions

        private

        def seed_variables(locals:, globals:)
          return unless variables.respond_to?(:set)

          if locals.is_a?(Hash)
            locals.each { |k, v| variables.set(k.to_s, v, scope: :local) }
          end

          if globals.is_a?(Hash)
            globals.each { |k, v| variables.set(k.to_s, v, scope: :global) }
          end
        end
      end
    end
  end
end
