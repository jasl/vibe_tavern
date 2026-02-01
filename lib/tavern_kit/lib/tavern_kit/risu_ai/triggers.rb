# frozen_string_literal: true

require_relative "triggers/helpers"
require_relative "triggers/v2_collection_effects"
require_relative "triggers/v2_string_effects"

module TavernKit
  module RisuAI
    # RisuAI trigger engine (Wave 5f).
    #
    # This starts with the v1-style trigger schema used by characterization
    # tests (conditions + effect array). v2 effects are added iteratively.
    module Triggers
      Result = Data.define(:chat)

      class LocalVars
        def initialize
          @by_indent = {}
        end

        def get(key, current_indent:)
          i = current_indent.to_i
          while i >= 0
            scope = @by_indent[i]
            return scope[key] if scope && scope.key?(key)

            i -= 1
          end

          nil
        end

        def set(key, value, indent:)
          final_value = value.nil? ? "null" : value.to_s

          found_indent = nil
          i = indent.to_i
          while i >= 0
            scope = @by_indent[i]
            if scope && scope.key?(key)
              found_indent = i
              break
            end
            i -= 1
          end

          target_indent = found_indent || indent.to_i
          (@by_indent[target_indent] ||= {})[key] = final_value
        end

        def clear_at_indent(indent)
          threshold = indent.to_i
          @by_indent.keys.each do |i|
            @by_indent.delete(i) if i >= threshold
          end
        end
      end

      # Upstream reference:
      # resources/Risuai/src/ts/process/triggers.ts (safeSubset/displayAllowList/requestAllowList)
      SAFE_SUBSET = %w[
        v2SetVar
        v2If
        v2IfAdvanced
        v2Else
        v2EndIndent
        v2LoopNTimes
        v2BreakLoop
        v2ConsoleLog
        v2StopTrigger
        v2Random
        v2ExtractRegex
        v2RegexTest
        v2GetCharAt
        v2GetCharCount
        v2ToLowerCase
        v2ToUpperCase
        v2SetCharAt
        v2SplitString
        v2JoinArrayVar
        v2ConcatString
        v2MakeArrayVar
        v2GetArrayVarLength
        v2GetArrayVar
        v2SetArrayVar
        v2PushArrayVar
        v2PopArrayVar
        v2ShiftArrayVar
        v2UnshiftArrayVar
        v2SpliceArrayVar
        v2SliceArrayVar
        v2GetIndexOfValueInArrayVar
        v2RemoveIndexFromArrayVar
        v2Calculate
        v2Comment
        v2DeclareLocalVar
      ].freeze

      DISPLAY_ALLOWLIST = (SAFE_SUBSET + %w[v2GetDisplayState v2SetDisplayState]).freeze
      REQUEST_ALLOWLIST = (SAFE_SUBSET + %w[v2GetRequestState v2SetRequestState v2GetRequestStateRole v2SetRequestStateRole v2GetRequestStateLength]).freeze

      module_function

      # Run a trigger list (the upstream "runTrigger" entrypoint).
      #
      # @param triggers [Array<Hash>] trigger scripts
      # @param chat [Hash] chat state (messages + scriptstate)
      # @param mode [String, Symbol, nil] optional type filter (e.g. "output")
      # @param manual_name [String, nil] runs only triggers whose comment matches (manual mode)
      # @param recursion_count [Integer] recursion guard for runtrigger
      def run_all(triggers, chat:, mode: nil, manual_name: nil, recursion_count: 0)
        t_list = normalize_triggers(triggers)
        c = deep_symbolize(chat.is_a?(Hash) ? chat : {})
        local_vars = LocalVars.new
        run_all_normalized(t_list, chat: c, mode: mode, manual_name: manual_name, recursion_count: recursion_count, local_vars: local_vars)
        Result.new(chat: c)
      end

      def run(trigger, chat:)
        t = TavernKit::Utils.deep_stringify_keys(trigger.is_a?(Hash) ? trigger : {})
        c = deep_symbolize(chat.is_a?(Hash) ? chat : {})

        # Note: `run` executes a single trigger unconditionally; it does not
        # filter by mode. However, request/display modes still apply effect
        # allowlists (mirroring upstream) to prevent unsafe side effects.
        _ = t.fetch("type", "").to_s

        conditions = Array(t["conditions"]).select { |v| v.is_a?(Hash) }
        effects = Array(t["effect"]).select { |v| v.is_a?(Hash) }

        local_vars = LocalVars.new

        return Result.new(chat: c) unless conditions_pass?(conditions, chat: c, local_vars: local_vars)

        run_effects(effects, chat: c, trigger: t, triggers: nil, recursion_count: 0, local_vars: local_vars)

        Result.new(chat: c)
      end

      def run_all_normalized(triggers, chat:, mode:, manual_name:, recursion_count:, local_vars:)
        triggers.each do |t|
          next unless t.is_a?(Hash)

          if manual_name
            next unless t["comment"].to_s == manual_name.to_s
          elsif mode
            next unless t["type"].to_s == mode.to_s
          end

          run_one_normalized(t, triggers: triggers, chat: chat, recursion_count: recursion_count, local_vars: local_vars)
        end
      end
      private_class_method :run_all_normalized

      def run_one_normalized(trigger, triggers:, chat:, recursion_count:, local_vars:)
        conditions = Array(trigger["conditions"]).select { |v| v.is_a?(Hash) }
        effects = Array(trigger["effect"]).select { |v| v.is_a?(Hash) }

        return unless conditions_pass?(conditions, chat: chat, local_vars: local_vars)

        run_effects(effects, chat: chat, trigger: trigger, triggers: triggers, recursion_count: recursion_count, local_vars: local_vars)
      end
      private_class_method :run_one_normalized

      def conditions_pass?(conditions, chat:, local_vars:)
        current_indent = 0

        conditions.all? do |condition|
          case condition["type"].to_s
          when "var", "chatindex", "value"
            check_var_condition(condition, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "exists"
            check_exists_condition(condition, chat: chat)
          else
            false
          end
        end
      end

      def check_var_condition(condition, chat:, local_vars:, current_indent:)
        var_value =
          case condition["type"].to_s
          when "var"
            get_var(chat, condition["var"], local_vars: local_vars, current_indent: current_indent) || "null"
          when "chatindex"
            Array(chat[:message]).length.to_s
          when "value"
            condition["var"].to_s
          else
            nil
          end

        return false if var_value.nil?

        operator = condition["operator"].to_s
        condition_value = condition["value"].to_s
        vv = var_value.to_s

        case operator
        when "true"
          vv == "true" || vv == "1"
        when "="
          vv == condition_value
        when "!="
          vv != condition_value
        when ">"
          vv.to_f > condition_value.to_f
        when "<"
          vv.to_f < condition_value.to_f
        when ">="
          vv.to_f >= condition_value.to_f
        when "<="
          vv.to_f <= condition_value.to_f
        when "null"
          vv == "null"
        else
          false
        end
      end

      def check_exists_condition(condition, chat:)
        val = condition["value"].to_s
        depth = Integer(condition["depth"] || 0) rescue 0
        type2 = condition["type2"].to_s

        msgs = Array(chat[:message])
        slice = depth > 0 ? msgs.last(depth) : msgs
        da = slice.map { |m| deep_symbolize(m)[:data].to_s }.join(" ")

        case type2
        when "strict"
          da.split(" ").include?(val)
        when "loose"
          da.downcase.include?(val.downcase)
        when "regex"
          Regexp.new(val).match?(da)
        else
          false
        end
      rescue RegexpError
        false
      end

      def apply_effect(effect, chat:, trigger:, triggers:, recursion_count:, local_vars:, current_indent:)
        case effect["type"].to_s
        when "setvar"
          apply_setvar(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
        when "systemprompt"
          apply_systemprompt(effect, chat: chat)
        when "impersonate"
          apply_impersonate(effect, chat: chat)
        when "stop"
          chat[:stop_sending] = true
        when "runtrigger"
          apply_runtrigger(effect, chat: chat, trigger: trigger, triggers: triggers, recursion_count: recursion_count)
        when "cutchat"
          apply_cutchat(effect, chat: chat)
        when "modifychat"
          apply_modifychat(effect, chat: chat)
        when "extractRegex"
          apply_extract_regex(effect, chat: chat, trigger: trigger, local_vars: local_vars, current_indent: current_indent)
        else
          nil
        end
      end

      def low_level_access?(trigger)
        trigger.is_a?(Hash) && trigger["lowLevelAccess"] == true
      end

      def run_effects(effects, chat:, trigger:, triggers:, recursion_count:, local_vars:)
        effect_idx = 0
        mode = trigger["type"].to_s
        current_indent = 0
        loop_n_times = Hash.new(0)

        while effect_idx < effects.length
          effect = effects[effect_idx]
          type = effect["type"].to_s
          unless effect_allowed?(type, mode: mode)
            effect_idx += 1
            next
          end

          indent_value = Integer(effect["indent"].to_s, exception: false)
          current_indent = indent_value && indent_value >= 0 ? indent_value : 0

          case type
          when "v2If", "v2IfAdvanced"
            indent = Integer(effect["indent"].to_s, exception: false) || 0
            pass = v2_if_pass?(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)

            unless pass
              # Skip until the matching end of this indent block.
              end_indent = indent + 1
              effect_idx += 1
              while effect_idx < effects.length
                ef = effects[effect_idx]
                if ef["type"].to_s == "v2EndIndent" && (Integer(ef["indent"].to_s, exception: false) || 0) == end_indent
                  # If there's an else clause, jump to it so the loop increment
                  # lands on the first else-body effect.
                  next_ef = effects[effect_idx + 1]
                  if next_ef.is_a?(Hash) && next_ef["type"].to_s == "v2Else" && (Integer(next_ef["indent"].to_s, exception: false) || 0) == indent
                    effect_idx += 1
                  end
                  break
                end

                effect_idx += 1
              end
            end
          when "v2SetVar"
            apply_v2_setvar(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2Random"
            apply_v2_random(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2RegexTest"
            apply_v2_regex_test(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2ExtractRegex"
            apply_v2_extract_regex(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2GetCharAt"
            apply_v2_get_char_at(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2GetCharCount"
            apply_v2_get_char_count(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2ToLowerCase"
            apply_v2_to_lower_case(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2ToUpperCase"
            apply_v2_to_upper_case(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2SetCharAt"
            apply_v2_set_char_at(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2ConcatString"
            apply_v2_concat_string(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2SplitString"
            apply_v2_split_string(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2JoinArrayVar"
            apply_v2_join_array_var(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2MakeDictVar", "v2ClearDict"
            apply_v2_make_dict_var(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2GetDictVar"
            apply_v2_get_dict_var(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2SetDictVar"
            apply_v2_set_dict_var(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2DeleteDictKey"
            apply_v2_delete_dict_key(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2HasDictKey"
            apply_v2_has_dict_key(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2GetDictSize"
            apply_v2_get_dict_size(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2GetDictKeys"
            apply_v2_get_dict_keys(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2GetDictValues"
            apply_v2_get_dict_values(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2MakeArrayVar"
            apply_v2_make_array_var(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2GetArrayVarLength"
            apply_v2_get_array_var_length(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2GetArrayVar"
            apply_v2_get_array_var(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2SetArrayVar"
            apply_v2_set_array_var(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2PushArrayVar"
            apply_v2_push_array_var(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2PopArrayVar"
            apply_v2_pop_array_var(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2ShiftArrayVar"
            apply_v2_shift_array_var(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2UnshiftArrayVar"
            apply_v2_unshift_array_var(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2SpliceArrayVar"
            apply_v2_splice_array_var(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2SliceArrayVar"
            apply_v2_slice_array_var(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2GetIndexOfValueInArrayVar"
            apply_v2_get_index_of_value_in_array_var(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2RemoveIndexFromArrayVar"
            apply_v2_remove_index_from_array_var(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2Calculate"
            apply_v2_calculate(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2ReplaceString"
            apply_v2_replace_string(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2GetDisplayState"
            # Upstream: works only in displayMode; TavernKit maps it to trigger type == "display".
            if mode == "display"
              value = chat[:display_data]
              set_var(chat, effect["outputVar"], value.nil? ? "null" : value.to_s, local_vars: local_vars, current_indent: current_indent)
            end
          when "v2SetDisplayState"
            if mode == "display"
              value =
                if effect["valueType"].to_s == "value"
                  effect["value"].to_s
                else
                  get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
                end
              chat[:display_data] = value
            end
          when "v2GetRequestState"
            if mode == "request"
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
          when "v2SetRequestState"
            if mode == "request"
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
          when "v2GetRequestStateRole"
            if mode == "request"
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
          when "v2SetRequestStateRole"
            if mode == "request"
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
              if role
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
            end
          when "v2GetRequestStateLength"
            if mode == "request"
              output_var = effect["outputVar"].to_s
              data = chat[:display_data].to_s

              begin
                json = ::JSON.parse(data)
                set_var(chat, output_var, Array(json).length.to_s, local_vars: local_vars, current_indent: current_indent)
              rescue JSON::ParserError, TypeError
                set_var(chat, output_var, "0", local_vars: local_vars, current_indent: current_indent)
              end
            end
          when "v2GetLastMessage"
            messages = Array(chat[:message])
            last = messages.last
            data = last.is_a?(Hash) ? last[:data].to_s : nil
            set_var(chat, effect["outputVar"], data.nil? ? "null" : data, local_vars: local_vars, current_indent: current_indent)
          when "v2GetLastUserMessage"
            messages = Array(chat[:message])
            last = messages.reverse.find { |m| m.is_a?(Hash) && m[:role].to_s == "user" }
            data = last.is_a?(Hash) ? last[:data].to_s : nil
            set_var(chat, effect["outputVar"], data.nil? ? "null" : data, local_vars: local_vars, current_indent: current_indent)
          when "v2GetLastCharMessage"
            messages = Array(chat[:message])
            last = messages.reverse.find { |m| m.is_a?(Hash) && m[:role].to_s == "char" }
            data = last.is_a?(Hash) ? last[:data].to_s : nil
            set_var(chat, effect["outputVar"], data.nil? ? "null" : data, local_vars: local_vars, current_indent: current_indent)
          when "v2GetFirstMessage"
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
          when "v2GetMessageAtIndex"
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
          when "v2GetMessageCount"
            set_var(chat, effect["outputVar"], Array(chat[:message]).length.to_s, local_vars: local_vars, current_indent: current_indent)
          when "v2CutChat"
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
          when "v2ModifyChat"
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
          when "v2SystemPrompt"
            value =
              if effect["valueType"].to_s == "value"
                effect["value"].to_s
              else
                get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            apply_systemprompt({ "location" => effect["location"], "value" => value }, chat: chat)
          when "v2Impersonate"
            value =
              if effect["valueType"].to_s == "value"
                effect["value"].to_s
              else
                get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            apply_impersonate({ "role" => effect["role"], "value" => value }, chat: chat)
          when "v2QuickSearchChat"
            apply_v2_quick_search_chat(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2Tokenize"
            apply_v2_tokenize(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2ConsoleLog"
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
          when "v2StopTrigger"
            break
          when "v2Comment"
            nil
          when "v2DeclareLocalVar"
            key = effect["var"].to_s.delete_prefix("$")
            value =
              if effect["valueType"].to_s == "value"
                effect["value"].to_s
              else
                get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent) || "null"
              end
            local_vars.set(key, value, indent: current_indent)
          when "v2StopPromptSending"
            chat[:stop_sending] = true
          when "v2Else"
            # Skip else body when the preceding v2IfAdvanced passed.
            else_indent = Integer(effect["indent"].to_s, exception: false) || 0
            end_indent = else_indent + 1
            effect_idx += 1
            while effect_idx < effects.length
              ef = effects[effect_idx]
              break if ef["type"].to_s == "v2EndIndent" && (Integer(ef["indent"].to_s, exception: false) || 0) == end_indent

              effect_idx += 1
            end
          when "v2EndIndent"
            end_indent = Integer(effect["indent"].to_s, exception: false) || 0

            if effect["endOfLoop"] == true
              loop_indent = end_indent - 1
              original_idx = effect_idx

              header_idx = nil
              scan = effect_idx
              while scan >= 0
                ef = effects[scan]
                ef_type = ef["type"].to_s
                ef_indent = Integer(ef["indent"].to_s, exception: false) || 0

                if (ef_type == "v2Loop" || ef_type == "v2LoopNTimes") && ef_indent == loop_indent
                  header_idx = scan

                  if ef_type == "v2LoopNTimes"
                    raw =
                      if ef["valueType"].to_s == "value"
                        ef["value"].to_s
                      else
                        get_var(chat, ef["value"], local_vars: local_vars, current_indent: end_indent) || "null"
                      end

                    max_times = safe_float(raw)
                    max_times = 0.0 if max_times.nan?

                    loop_n_times[header_idx] += 1
                    if loop_n_times[header_idx] < max_times
                      effect_idx = header_idx
                    else
                      effect_idx = original_idx
                    end
                  else
                    effect_idx = header_idx
                  end

                  break
                end

                scan -= 1
              end
            end

            local_vars.clear_at_indent(end_indent)
          when "v2Loop", "v2LoopNTimes"
            # Looping is handled by v2EndIndent (mirrors upstream).
            nil
          when "v2BreakLoop"
            scan = effect_idx
            while scan < effects.length
              ef = effects[scan]
              if ef["type"].to_s == "v2EndIndent" && ef["endOfLoop"] == true
                effect_idx = scan
                break
              end
              scan += 1
            end
          else
            if type.start_with?("v2")
              # ignore unknown v2 effects until needed by tests
              nil
            else
              apply_effect(
                effect,
                chat: chat,
                trigger: trigger,
                triggers: triggers,
                recursion_count: recursion_count,
                local_vars: local_vars,
                current_indent: current_indent,
              )
            end
          end

          effect_idx += 1
        end
      end

      # Helper methods are split into `risu_ai/triggers/helpers.rb` (Wave 6).
    end
  end
end
