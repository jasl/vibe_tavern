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
        attr_reader :character, :user, :variables, :outlets, :original, :clock, :rng, :content_hash, :extensions, :post_process

        def initialize(
          character: nil,
          user: nil,
          variables: TavernKit::ChatVariables::InMemory.new,
          outlets: {},
          original: nil,
          clock: nil,
          rng: nil,
          content_hash: nil,
          extensions: {},
          post_process: nil,
          **_platform_attrs
        )
          @character = character
          @user = user
          @variables = variables || TavernKit::ChatVariables::InMemory.new
          @outlets = outlets.is_a?(Hash) ? outlets : {}
          @original = original.nil? ? nil : original.to_s

          @clock =
            if clock.nil?
              -> { Time.now }
            elsif clock.respond_to?(:call)
              clock
            else
              -> { clock }
            end

          @rng = rng || Random.new
          @content_hash = content_hash
          @extensions = extensions.is_a?(Hash) ? TavernKit::Utils.deep_stringify_keys(extensions) : {}

          @post_process =
            if post_process.respond_to?(:call)
              post_process
            else
              ->(s) { s.to_s }
            end
        end

        def character_name
          if character.respond_to?(:display_name)
            character.display_name.to_s
          elsif character.respond_to?(:name)
            character.name.to_s
          else
            ""
          end
        end

        def user_name
          user.respond_to?(:name) ? user.name.to_s : ""
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
      end
    end
  end
end
