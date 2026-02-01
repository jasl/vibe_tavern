# frozen_string_literal: true

module TavernKit
  module RisuAI
    # Internal helper methods for the trigger engine.
    #
    # Pure refactor: extracted from `risu_ai/triggers/helpers.rb` to keep file sizes
    # manageable (Wave 6 large-file split).
    module Triggers
      module_function

      def effect_allowed?(effect_type, mode:)
        case mode.to_s
        when "display"
          DISPLAY_ALLOWLIST.include?(effect_type)
        when "request"
          REQUEST_ALLOWLIST.include?(effect_type)
        else
          true
        end
      end

      def v2_if_pass?(effect, chat:, local_vars:, current_indent:)
        source_value =
          if effect["sourceType"].to_s == "value"
            effect["source"].to_s
          else
            get_var(chat, effect["source"], local_vars: local_vars, current_indent: current_indent)
          end

        target_value =
          if effect["targetType"].to_s == "value"
            effect["target"].to_s
          else
            get_var(chat, effect["target"], local_vars: local_vars, current_indent: current_indent)
          end

        condition = effect["condition"].to_s

        case condition
        when "="
          numeric_equal?(source_value, target_value)
        when "!="
          !numeric_equal?(source_value, target_value)
        when "∈"
          ::JSON.parse(target_value.to_s).include?(source_value.to_s)
        when "∋"
          ::JSON.parse(source_value.to_s).include?(target_value.to_s)
        when "∉"
          !::JSON.parse(target_value.to_s).include?(source_value.to_s)
        when "∌"
          !::JSON.parse(source_value.to_s).include?(target_value.to_s)
        when ">"
          numeric_compare?(source_value, target_value, :>)
        when "<"
          numeric_compare?(source_value, target_value, :<)
        when ">="
          numeric_compare?(source_value, target_value, :>=)
        when "<="
          numeric_compare?(source_value, target_value, :<=)
        when "≒"
          approx_equal?(source_value, target_value)
        when "≡"
          equivalent?(source_value, target_value)
        else
          false
        end
      rescue JSON::ParserError
        false
      end

      def apply_v2_setvar(effect, chat:, local_vars:, current_indent:)
        key = effect["var"].to_s
        operator = effect["operator"].to_s
        value =
          if effect["valueType"].to_s == "value"
            effect["value"].to_s
          else
            get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent)
          end

        original = safe_float(get_var(chat, key, local_vars: local_vars, current_indent: current_indent))
        original = 0.0 if original.nan?

        delta = safe_float(value)

        result =
          case operator
          when "="
            value.to_s
          when "+="
            format_js_number(original + delta)
          when "-="
            format_js_number(original - delta)
          when "*="
            format_js_number(original * delta)
          when "/="
            format_js_number(original / delta)
          when "%="
            format_js_number(original % delta)
          else
            value.to_s
          end

        set_var(chat, key, result, local_vars: local_vars, current_indent: current_indent)
      end

      def apply_setvar(effect, chat:, local_vars:, current_indent:)
        key = effect["var"].to_s
        value = effect["value"].to_s
        operator = effect["operator"].to_s

        original = safe_float(get_var(chat, key, local_vars: local_vars, current_indent: current_indent))
        original = 0.0 if original.nan?

        delta = safe_float(value)

        result =
          case operator
          when "="
            value
          when "+="
            format_js_number(original + delta)
          when "-="
            format_js_number(original - delta)
          when "*="
            format_js_number(original * delta)
          when "/="
            format_js_number(original / delta)
          when "%="
            format_js_number(original % delta)
          else
            value
          end

        set_var(chat, key, result, local_vars: local_vars, current_indent: current_indent)
      end

      def apply_systemprompt(effect, chat:)
        location = effect["location"].to_s
        value = effect["value"].to_s

        bucket = chat[:additional_sys_prompt]
        bucket = {} unless bucket.is_a?(Hash)
        chat[:additional_sys_prompt] = bucket

        key =
          case location
          when "start"
            :start
          when "historyend"
            :historyend
          when "promptend"
            :promptend
          else
            nil
          end

        return unless key

        bucket[key] = "#{bucket[key]}#{value}\n\n"
      end

      def apply_impersonate(effect, chat:)
        role = effect["role"].to_s
        value = effect["value"].to_s

        normalized_role =
          case role
          when "user"
            "user"
          when "char"
            "char"
          else
            nil
          end
        return unless normalized_role

        messages = chat[:message]
        messages = [] unless messages.is_a?(Array)
        chat[:message] = messages

        messages << { role: normalized_role, data: value }
      end

      def apply_cutchat(effect, chat:)
        start_idx = Integer(effect["start"].to_s, exception: false) || 0
        end_idx = Integer(effect["end"].to_s, exception: false)

        messages = chat[:message]
        messages = [] unless messages.is_a?(Array)

        if end_idx.nil?
          chat[:message] = messages[start_idx..] || []
        else
          chat[:message] = messages[start_idx...end_idx] || []
        end
      end

      def apply_modifychat(effect, chat:)
        idx = Integer(effect["index"].to_s, exception: false)
        return unless idx

        value = effect["value"].to_s

        messages = chat[:message]
        return unless messages.is_a?(Array)

        msg = messages[idx]
        return unless msg.is_a?(Hash)

        msg[:data] = value
        messages[idx] = msg
      end

      def apply_runtrigger(effect, chat:, trigger:, triggers:, recursion_count:)
        return unless triggers.is_a?(Array)

        name = effect["value"].to_s
        return if name.empty?

        if recursion_count >= 10 && !low_level_access?(trigger)
          return
        end

        local_vars = LocalVars.new
        run_all_normalized(
          triggers,
          chat: chat,
          mode: :manual,
          manual_name: name,
          recursion_count: recursion_count + 1,
          local_vars: local_vars,
        )
      end

      def apply_extract_regex(effect, chat:, trigger:, local_vars:, current_indent:)
        return unless low_level_access?(trigger)

        text = effect["value"].to_s
        pattern = effect["regex"].to_s
        flags = effect["flags"].to_s
        out = effect["result"].to_s
        input_var = effect["inputVar"].to_s

        re = TavernKit::RegexSafety.compile(pattern, options: regex_options(flags))
        match = re ? TavernKit::RegexSafety.match(re, text) : nil
        return unless match

        result = out.gsub(/\$\d+/) do |m|
          idx = Integer(m.delete_prefix("$"), exception: false)
          idx && match[idx] ? match[idx].to_s : ""
        end
        result = result.gsub("$&", match[0].to_s)
        result = result.gsub("$$", "$")

        set_var(chat, input_var, result, local_vars: local_vars, current_indent: current_indent)
      end

      def regex_options(flags)
        opts = 0
        opts |= Regexp::IGNORECASE if flags.include?("i")
        opts |= Regexp::MULTILINE if flags.include?("m")
        opts
      end

      def v2_replace_string_replacement(match, result_format, replacement)
        match_str = match[0].to_s
        groups = match.captures

        target_group_match = result_format.match(/\A\$(\d+)\z/)
        if target_group_match
          target_index = Integer(target_group_match[1], exception: false)
          if target_index == 0
            return replacement
          elsif target_index
            target_group = groups[target_index - 1]
            if target_group && !target_group.empty?
              return match_str.sub(target_group, replacement)
            end
          end
        end

        result_format.gsub(/\$\d+/) do |placeholder|
          idx = Integer(placeholder.delete_prefix("$"), exception: false)
          idx == 0 ? match_str : (idx ? (groups[idx - 1] || "") : "")
        end
          .gsub("$&", match_str)
          .gsub("$$", "$")
      end
    end
  end
end
