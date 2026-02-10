# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      module Macros
        module_function

        def resolve_trigger_id(environment)
          meta = environment.respond_to?(:metadata) ? environment.metadata : nil
          return "null" unless meta.is_a?(Hash)

          value = meta["triggerid"]
          value.nil? ? "null" : value.to_s
        end
        private_class_method :resolve_trigger_id

        def resolve_firstmsgindex(environment)
          idx = environment.respond_to?(:greeting_index) ? environment.greeting_index : nil
          idx.nil? ? "-1" : idx.to_i.to_s
        end
        private_class_method :resolve_firstmsgindex

        def resolve_isfirstmsg(environment)
          conds = environment.respond_to?(:cbs_conditions) ? environment.cbs_conditions : nil
          first = conds.is_a?(Hash) ? conds["firstmsg"] : nil
          TavernKit::Coerce.bool(first, default: false) ? "1" : "0"
        rescue StandardError
          "0"
        end
        private_class_method :resolve_isfirstmsg

        def resolve_blank(_args)
          ""
        end
        private_class_method :resolve_blank

        def resolve_lastmessage(environment)
          msg = normalized_history(environment).last
          msg ? msg[:data].to_s : ""
        end
        private_class_method :resolve_lastmessage

        def resolve_lastmessageid(environment)
          list = normalized_history(environment)
          return "" if list.empty?

          (list.length - 1).to_s
        end
        private_class_method :resolve_lastmessageid

        def resolve_previouscharchat(environment)
          list = normalized_history(environment)

          pointer =
            if environment.respond_to?(:chat_index) && environment.chat_index.to_i != -1
              environment.chat_index.to_i - 1
            else
              list.length - 1
            end

          while pointer >= 0
            msg = list[pointer]
            return msg[:data].to_s if char_role?(msg[:role])

            pointer -= 1
          end

          greeting_fallback(environment)
        end
        private_class_method :resolve_previouscharchat

        def resolve_previoususerchat(environment)
          chat_index = environment.respond_to?(:chat_index) ? environment.chat_index.to_i : -1
          return "" if chat_index == -1

          list = normalized_history(environment)
          pointer = chat_index - 1

          while pointer >= 0
            msg = list[pointer]
            return msg[:data].to_s if user_role?(msg[:role])

            pointer -= 1
          end

          greeting_fallback(environment)
        end
        private_class_method :resolve_previoususerchat

        def normalized_history(environment)
          raw = environment.respond_to?(:history) ? environment.history : nil
          return [] if raw.nil?

          list =
            if raw.is_a?(Array)
              raw
            elsif raw.respond_to?(:to_a)
              raw.to_a
            else
              []
            end

          list.filter_map { |m| normalize_history_message(m) }
        rescue ArgumentError
          []
        end
        private_class_method :normalized_history

        def normalize_history_message(message)
          case message
          when TavernKit::PromptBuilder::Message
            { role: message.role, data: message.content.to_s }
          when TavernKit::PromptBuilder::Block
            { role: message.role, data: message.content.to_s }
          when Hash
            h = TavernKit::PromptBuilder::Context.normalize(message)
            role = h[:role]
            data = h[:data] || h[:content] || h[:text] || ""
            { role: role, data: data.to_s }
          else
            if message.respond_to?(:role) && message.respond_to?(:content)
              return { role: message.role, data: message.content.to_s }
            end
            if message.respond_to?(:role) && message.respond_to?(:data)
              return { role: message.role, data: message.data.to_s }
            end
            nil
          end
        rescue StandardError
          nil
        end
        private_class_method :normalize_history_message

        def user_role?(role)
          role.to_s == "user"
        end
        private_class_method :user_role?

        def char_role?(role)
          r = role.to_s
          r == "assistant" || r == "char" || r == "bot"
        end
        private_class_method :char_role?

        def greeting_fallback(environment)
          char = environment.respond_to?(:character) ? environment.character : nil
          return "" unless char&.respond_to?(:data)

          data = char.data
          first = data.respond_to?(:first_mes) ? data.first_mes.to_s : ""
          alts = data.respond_to?(:alternate_greetings) ? Array(data.alternate_greetings) : []

          idx = environment.respond_to?(:greeting_index) ? environment.greeting_index : nil
          return first if idx.nil? || idx.to_i == -1

          alts[idx.to_i].to_s.strip.empty? ? first : alts[idx.to_i].to_s
        rescue StandardError
          ""
        end
        private_class_method :greeting_fallback
      end
    end
  end
end
