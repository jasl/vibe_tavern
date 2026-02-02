# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Triggers
      # Trigger effect runner (v1 + v2 schema).
      #
      # Pure refactor: extracted from `risu_ai/triggers.rb` to keep file sizes
      # manageable (Wave 6 large-file split).

      module_function

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
            apply_v2_get_display_state(effect, chat: chat, local_vars: local_vars, current_indent: current_indent, mode: mode)
          when "v2SetDisplayState"
            apply_v2_set_display_state(effect, chat: chat, local_vars: local_vars, current_indent: current_indent, mode: mode)
          when "v2GetRequestState"
            apply_v2_get_request_state(effect, chat: chat, local_vars: local_vars, current_indent: current_indent, mode: mode)
          when "v2SetRequestState"
            apply_v2_set_request_state(effect, chat: chat, local_vars: local_vars, current_indent: current_indent, mode: mode)
          when "v2GetRequestStateRole"
            apply_v2_get_request_state_role(effect, chat: chat, local_vars: local_vars, current_indent: current_indent, mode: mode)
          when "v2SetRequestStateRole"
            apply_v2_set_request_state_role(effect, chat: chat, local_vars: local_vars, current_indent: current_indent, mode: mode)
          when "v2GetRequestStateLength"
            apply_v2_get_request_state_length(effect, chat: chat, local_vars: local_vars, current_indent: current_indent, mode: mode)
          when "v2GetLastMessage"
            apply_v2_get_last_message(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2GetLastUserMessage"
            apply_v2_get_last_user_message(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2GetLastCharMessage"
            apply_v2_get_last_char_message(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2GetFirstMessage"
            apply_v2_get_first_message(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2GetMessageAtIndex"
            apply_v2_get_message_at_index(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2GetMessageCount"
            apply_v2_get_message_count(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2CutChat"
            apply_v2_cut_chat(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2ModifyChat"
            apply_v2_modify_chat(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2SystemPrompt"
            apply_v2_system_prompt(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2Impersonate"
            apply_v2_impersonate(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2QuickSearchChat"
            apply_v2_quick_search_chat(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2Tokenize"
            apply_v2_tokenize(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2ConsoleLog"
            apply_v2_console_log(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
          when "v2StopTrigger"
            break
          when "v2Comment"
            nil
          when "v2DeclareLocalVar"
            apply_v2_declare_local_var(effect, local_vars: local_vars, chat: chat, current_indent: current_indent)
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
    end
  end
end
