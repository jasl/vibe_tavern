# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      # Small subset of the CBS macro registry (Wave 5b).
      #
      # Upstream reference:
      # resources/Risuai/src/ts/cbs.ts (registerFunction)
      module Macros
        module_function

        def resolve(name, args, environment:)
          key = normalize_name(name)

          case key
          when "char", "bot"
            resolve_char(environment)
          when "user"
            resolve_user(environment)
          when "prefillsupported", "prefill_supported", "prefill"
            resolve_prefill_supported(environment)
          else
            nil
          end
        end

        def normalize_name(name)
          name.to_s.downcase.strip
        end
        private_class_method :normalize_name

        def resolve_char(environment)
          char = environment.respond_to?(:character) ? environment.character : nil
          return environment.character_name.to_s if char.nil?

          if char.respond_to?(:display_name)
            char.display_name.to_s
          elsif char.respond_to?(:name)
            char.name.to_s
          else
            environment.character_name.to_s
          end
        end
        private_class_method :resolve_char

        def resolve_user(environment)
          user = environment.respond_to?(:user) ? environment.user : nil
          return environment.user_name.to_s if user.nil?

          user.respond_to?(:name) ? user.name.to_s : environment.user_name.to_s
        end
        private_class_method :resolve_user

        def resolve_prefill_supported(environment)
          # Upstream checks for Claude models (db.aiModel.startsWith('claude')) and
          # returns "1"/"0". TavernKit approximates this using dialect/model_hint.
          dialect = environment.respond_to?(:dialect) ? environment.dialect : nil
          model_hint = environment.respond_to?(:model_hint) ? environment.model_hint.to_s : ""

          supported =
            dialect.to_s == "anthropic" ||
            model_hint.downcase.start_with?("claude") ||
            model_hint.downcase.include?("claude-")

          supported ? "1" : "0"
        end
        private_class_method :resolve_prefill_supported
      end
    end
  end
end
