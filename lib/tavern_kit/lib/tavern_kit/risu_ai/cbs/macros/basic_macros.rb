# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      module Macros
        module_function

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

        def resolve_chatindex(environment)
          (environment.respond_to?(:chat_index) ? (environment.chat_index || -1) : -1).to_i.to_s
        end
        private_class_method :resolve_chatindex

        def resolve_messageindex(environment)
          (environment.respond_to?(:message_index) ? (environment.message_index || 0) : 0).to_i.to_s
        end
        private_class_method :resolve_messageindex

        def resolve_personality(environment)
          char = environment.respond_to?(:character) ? environment.character : nil
          text = char&.respond_to?(:data) ? char.data&.personality.to_s : ""
          render_nested(text, environment: environment)
        end
        private_class_method :resolve_personality

        def resolve_description(environment)
          char = environment.respond_to?(:character) ? environment.character : nil
          text = char&.respond_to?(:data) ? char.data&.description.to_s : ""
          render_nested(text, environment: environment)
        end
        private_class_method :resolve_description

        def resolve_scenario(environment)
          char = environment.respond_to?(:character) ? environment.character : nil
          text = char&.respond_to?(:data) ? char.data&.scenario.to_s : ""
          render_nested(text, environment: environment)
        end
        private_class_method :resolve_scenario

        def resolve_exampledialogue(environment)
          char = environment.respond_to?(:character) ? environment.character : nil
          text = char&.respond_to?(:data) ? char.data&.mes_example.to_s : ""
          render_nested(text, environment: environment)
        end
        private_class_method :resolve_exampledialogue

        def resolve_persona(environment)
          user = environment.respond_to?(:user) ? environment.user : nil
          text = user&.respond_to?(:persona_text) ? user.persona_text.to_s : environment.user_name.to_s
          render_nested(text, environment: environment)
        end
        private_class_method :resolve_persona

        def resolve_model(environment)
          environment.respond_to?(:model_hint) ? environment.model_hint.to_s : ""
        end
        private_class_method :resolve_model

        def resolve_role(environment)
          # Upstream reference:
          # resources/Risuai/src/ts/cbs.ts (role)

          conds = environment.respond_to?(:cbs_conditions) ? environment.cbs_conditions : nil
          if conds.is_a?(Hash)
            chat_role = conds["chatrole"]
            return chat_role.to_s unless chat_role.nil? || chat_role.to_s.empty?

            return "char" if TavernKit::Coerce.bool(conds["firstmsg"], default: false)
          end

          chat_index = environment.respond_to?(:chat_index) ? environment.chat_index.to_i : -1
          if chat_index != -1
            raw_history = environment.respond_to?(:history) ? environment.history : nil
            list =
              if raw_history.is_a?(Array)
                raw_history
              elsif raw_history.respond_to?(:to_a)
                raw_history.to_a
              else
                []
              end

            msg = list[chat_index]
            if msg.is_a?(Hash)
              h = TavernKit::Runtime::Base.normalize(msg)
              role = h[:role]
              return role.to_s if role
            elsif msg && msg.respond_to?(:role)
              return msg.role.to_s
            end
          end

          role = environment.respond_to?(:role) ? environment.role : nil
          role.nil? ? "null" : role.to_s
        end
        private_class_method :resolve_role

        def resolve_metadata(args, environment:)
          key_raw = args[0].to_s
          key = normalize_name(key_raw)

          metadata =
            if environment.respond_to?(:metadata)
              environment.metadata
            else
              nil
            end

          unless metadata.is_a?(Hash) && metadata.key?(key)
            return "Error: #{key_raw} is not a valid metadata key."
          end

          value = metadata[key]
          return value ? "1" : "0" if value == true || value == false

          value.is_a?(Hash) || value.is_a?(Array) ? ::JSON.generate(value) : value.to_s
        end
        private_class_method :resolve_metadata

        def resolve_iserror(args)
          args[0].to_s.downcase.start_with?("error:") ? "1" : "0"
        end
        private_class_method :resolve_iserror
      end
    end
  end
end
