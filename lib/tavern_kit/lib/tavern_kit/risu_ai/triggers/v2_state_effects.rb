# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Triggers
      # V2 trigger effects that interact with chat/request state and history.
      #
      # Pure refactor: extracted from `risu_ai/triggers/runner.rb` to keep files
      # smaller and to isolate the "stateful" v2 effects from control-flow logic.

      module_function

      def apply_v2_get_display_state(effect, chat:, local_vars:, current_indent:, mode:)
        return unless mode == "display"

        value = chat[:display_data]
        set_var(chat, effect["outputVar"], value.nil? ? "null" : value.to_s, local_vars: local_vars, current_indent: current_indent)
      end

      def apply_v2_set_display_state(effect, chat:, local_vars:, current_indent:, mode:)
        return unless mode == "display"

        value =
          if effect["valueType"].to_s == "value"
            effect["value"].to_s
          else
            get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
          end
        chat[:display_data] = value
      end

      def apply_v2_get_request_state(effect, chat:, local_vars:, current_indent:, mode:)
        return unless mode == "request"

        index =
          if effect["indexType"].to_s == "value"
            safe_float(effect["index"])
          else
            safe_float(get_var(chat, effect["index"], local_vars: local_vars, current_indent: current_indent))
          end

        output_var = effect["outputVar"].to_s
        data = chat[:display_data].to_s

        begin
          json = ::JSON.parse(data)
          i = index.nan? || index.infinite? || !(index % 1).zero? || index.negative? ? nil : index.to_i
          content = i.nil? ? nil : json.dig(i, "content")
          set_var(chat, output_var, content.nil? ? "null" : content.to_s, local_vars: local_vars, current_indent: current_indent)
        rescue JSON::ParserError, TypeError
          set_var(chat, output_var, "null", local_vars: local_vars, current_indent: current_indent)
        end
      end

      def apply_v2_set_request_state(effect, chat:, local_vars:, current_indent:, mode:)
        return unless mode == "request"

        index =
          if effect["indexType"].to_s == "value"
            safe_float(effect["index"])
          else
            safe_float(get_var(chat, effect["index"], local_vars: local_vars, current_indent: current_indent))
          end

        value =
          if effect["valueType"].to_s == "value"
            effect["value"].to_s
          else
            get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
          end

        data = chat[:display_data].to_s
        begin
          json = ::JSON.parse(data)
          i = index.nan? || index.infinite? || !(index % 1).zero? || index.negative? ? nil : index.to_i
          if i && json[i].is_a?(Hash)
            json[i]["content"] = value
            chat[:display_data] = ::JSON.generate(json)
          end
        rescue JSON::ParserError, TypeError
          nil
        end
      end

      def apply_v2_get_request_state_role(effect, chat:, local_vars:, current_indent:, mode:)
        return unless mode == "request"

        index =
          if effect["indexType"].to_s == "value"
            safe_float(effect["index"])
          else
            safe_float(get_var(chat, effect["index"], local_vars: local_vars, current_indent: current_indent))
          end

        output_var = effect["outputVar"].to_s
        data = chat[:display_data].to_s

        begin
          json = ::JSON.parse(data)
          i = index.nan? || index.infinite? || !(index % 1).zero? || index.negative? ? nil : index.to_i
          role = i.nil? ? nil : json.dig(i, "role")
          set_var(chat, output_var, role.nil? ? "null" : role.to_s, local_vars: local_vars, current_indent: current_indent)
        rescue JSON::ParserError, TypeError
          set_var(chat, output_var, "null", local_vars: local_vars, current_indent: current_indent)
        end
      end

      def apply_v2_set_request_state_role(effect, chat:, local_vars:, current_indent:, mode:)
        return unless mode == "request"

        index =
          if effect["indexType"].to_s == "value"
            safe_float(effect["index"])
          else
            safe_float(get_var(chat, effect["index"], local_vars: local_vars, current_indent: current_indent))
          end

        value =
          if effect["valueType"].to_s == "value"
            effect["value"].to_s
          else
            get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
          end

        role = value if %w[user assistant system].include?(value)
        return unless role

        data = chat[:display_data].to_s
        begin
          json = ::JSON.parse(data)
          i = index.nan? || index.infinite? || !(index % 1).zero? || index.negative? ? nil : index.to_i
          if i && json[i].is_a?(Hash)
            json[i]["role"] = role
            chat[:display_data] = ::JSON.generate(json)
          end
        rescue JSON::ParserError, TypeError
          nil
        end
      end

      def apply_v2_get_request_state_length(effect, chat:, local_vars:, current_indent:, mode:)
        return unless mode == "request"

        output_var = effect["outputVar"].to_s
        data = chat[:display_data].to_s

        begin
          json = ::JSON.parse(data)
          set_var(chat, output_var, Array(json).length.to_s, local_vars: local_vars, current_indent: current_indent)
        rescue JSON::ParserError, TypeError
          set_var(chat, output_var, "0", local_vars: local_vars, current_indent: current_indent)
        end
      end

      def apply_v2_get_last_message(effect, chat:, local_vars:, current_indent:)
        messages = Array(chat[:message])
        last = messages.last
        data = last.is_a?(Hash) ? last[:data].to_s : nil
        set_var(chat, effect["outputVar"], data.nil? ? "null" : data, local_vars: local_vars, current_indent: current_indent)
      end

      def apply_v2_get_last_user_message(effect, chat:, local_vars:, current_indent:)
        messages = Array(chat[:message])
        last = messages.reverse.find { |m| m.is_a?(Hash) && m[:role].to_s == "user" }
        data = last.is_a?(Hash) ? last[:data].to_s : nil
        set_var(chat, effect["outputVar"], data.nil? ? "null" : data, local_vars: local_vars, current_indent: current_indent)
      end

      def apply_v2_get_last_char_message(effect, chat:, local_vars:, current_indent:)
        messages = Array(chat[:message])
        last = messages.reverse.find { |m| m.is_a?(Hash) && m[:role].to_s == "char" }
        data = last.is_a?(Hash) ? last[:data].to_s : nil
        set_var(chat, effect["outputVar"], data.nil? ? "null" : data, local_vars: local_vars, current_indent: current_indent)
      end

      def apply_v2_get_first_message(effect, chat:, local_vars:, current_indent:)
        fm_index = Integer(chat[:fmIndex].to_s, exception: false) || -1

        character = chat[:character]
        data = character&.respond_to?(:data) ? character.data : nil

        first = data&.respond_to?(:first_mes) ? data.first_mes.to_s : ""
        alternates = data&.respond_to?(:alternate_greetings) ? Array(data.alternate_greetings) : []

        out =
          if fm_index == -1
            first
          else
            msg = alternates[fm_index]
            msg.nil? ? "null" : msg.to_s
          end

        set_var(chat, effect["outputVar"], out, local_vars: local_vars, current_indent: current_indent)
      end

      def apply_v2_get_message_at_index(effect, chat:, local_vars:, current_indent:)
        raw_index =
          if effect["indexType"].to_s == "value"
            effect["index"].to_s
          else
            get_var(chat, effect["index"], local_vars: local_vars, current_indent: current_indent).to_s
          end

        index = safe_float(raw_index)
        messages = Array(chat[:message])
        msg =
          if index.nan? || index.infinite? || !(index % 1).zero? || index.negative?
            nil
          else
            messages[index.to_i]
          end

        data = msg.is_a?(Hash) ? msg[:data].to_s : nil
        set_var(chat, effect["outputVar"], data.nil? ? "null" : data, local_vars: local_vars, current_indent: current_indent)
      end

      def apply_v2_get_message_count(effect, chat:, local_vars:, current_indent:)
        set_var(chat, effect["outputVar"], Array(chat[:message]).length.to_s, local_vars: local_vars, current_indent: current_indent)
      end

      def apply_v2_cut_chat(effect, chat:, local_vars:, current_indent:)
        raw_start =
          if effect["startType"].to_s == "value"
            effect["start"].to_s
          else
            get_var(chat, effect["start"], local_vars: local_vars, current_indent: current_indent).to_s
          end

        raw_end =
          if effect["endType"].to_s == "value"
            effect["end"].to_s
          else
            get_var(chat, effect["end"], local_vars: local_vars, current_indent: current_indent).to_s
          end

        messages = Array(chat[:message])
        len = messages.length

        start = safe_float(raw_start)
        end_v = safe_float(raw_end)

        start_i = start.nan? ? 0 : js_slice_index(start, len)
        end_i = end_v.nan? ? len : js_slice_index(end_v, len)

        chat[:message] = messages[start_i...end_i] || []
      end

      def apply_v2_modify_chat(effect, chat:, local_vars:, current_indent:)
        raw_index =
          if effect["indexType"].to_s == "value"
            effect["index"].to_s
          else
            get_var(chat, effect["index"], local_vars: local_vars, current_indent: current_indent).to_s
          end

        value =
          if effect["valueType"].to_s == "value"
            effect["value"].to_s
          else
            get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
          end

        index = safe_float(raw_index)
        messages = Array(chat[:message])

        if !index.nan? && !index.infinite? && (index % 1).zero? && index >= 0
          i = index.to_i
          if (msg = messages[i]).is_a?(Hash)
            msg[:data] = value
            messages[i] = msg
            chat[:message] = messages
          end
        end
      end

      def apply_v2_system_prompt(effect, chat:, local_vars:, current_indent:)
        value =
          if effect["valueType"].to_s == "value"
            effect["value"].to_s
          else
            get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
          end

        apply_systemprompt({ "location" => effect["location"], "value" => value }, chat: chat)
      end

      def apply_v2_impersonate(effect, chat:, local_vars:, current_indent:)
        value =
          if effect["valueType"].to_s == "value"
            effect["value"].to_s
          else
            get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
          end

        apply_impersonate({ "role" => effect["role"], "value" => value }, chat: chat)
      end

      def apply_v2_console_log(effect, chat:, local_vars:, current_indent:)
        source =
          if effect["sourceType"].to_s == "value"
            effect["source"].to_s
          else
            get_var(chat, effect["source"], local_vars: local_vars, current_indent: current_indent).to_s
          end

        buf = chat[:console_log]
        buf = [] unless buf.is_a?(Array)
        buf << source
        chat[:console_log] = buf
      end

      def apply_v2_declare_local_var(effect, local_vars:, chat:, current_indent:)
        key = effect["var"].to_s.delete_prefix("$")
        value =
          if effect["valueType"].to_s == "value"
            effect["value"].to_s
          else
            get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent) || "null"
          end
        local_vars.set(key, value, indent: current_indent)
      end
    end
  end
end
