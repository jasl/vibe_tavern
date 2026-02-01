# frozen_string_literal: true

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
            min =
              if effect["minType"].to_s == "value"
                safe_float(effect["min"])
              else
                safe_float(get_var(chat, effect["min"], local_vars: local_vars, current_indent: current_indent))
              end

            max =
              if effect["maxType"].to_s == "value"
                safe_float(effect["max"])
              else
                safe_float(get_var(chat, effect["max"], local_vars: local_vars, current_indent: current_indent))
              end

            output_var = effect["outputVar"].to_s

            if min.nan? || max.nan?
              set_var(chat, output_var, "NaN", local_vars: local_vars, current_indent: current_indent)
            else
              value = (Random.rand * (max - min + 1) + min)
              floored =
                if value.infinite?
                  value
                else
                  value.floor
                end

              set_var(chat, output_var, format_js_number(floored), local_vars: local_vars, current_indent: current_indent)
            end
          when "v2RegexTest"
            value =
              if effect["valueType"].to_s == "value"
                effect["value"].to_s
              else
                get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            pattern =
              if effect["regexType"].to_s == "value"
                effect["regex"].to_s
              else
                get_var(chat, effect["regex"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            flags =
              if effect["flagsType"].to_s == "value"
                effect["flags"].to_s
              else
                get_var(chat, effect["flags"], local_vars: local_vars, current_indent: current_indent).to_s
              end
            hit =
              begin
                re = Regexp.new(pattern, regex_options(flags))
                re.match?(value) ? "1" : "0"
              rescue RegexpError
                "0"
              end

            set_var(chat, effect["outputVar"], hit, local_vars: local_vars, current_indent: current_indent)
          when "v2ExtractRegex"
            value =
              if effect["valueType"].to_s == "value"
                effect["value"].to_s
              else
                get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            pattern =
              if effect["regexType"].to_s == "value"
                effect["regex"].to_s
              else
                get_var(chat, effect["regex"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            flags =
              if effect["flagsType"].to_s == "value"
                effect["flags"].to_s
              else
                get_var(chat, effect["flags"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            format =
              if effect["resultType"].to_s == "value"
                effect["result"].to_s
              else
                get_var(chat, effect["result"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            re = Regexp.new(pattern, regex_options(flags))
            match = re.match(value)

            result =
              if match
                format.gsub(/\$\d+/) do |m|
                  group_idx = Integer(m.delete_prefix("$"), exception: false)
                  group_idx && match[group_idx] ? match[group_idx].to_s : ""
                end
                  .gsub("$&", match[0].to_s)
                  .gsub("$$", "$")
              else
                format.gsub(/\$\d+/, "")
                  .gsub("$&", "")
                  .gsub("$$", "$")
              end

            set_var(chat, effect["outputVar"], result, local_vars: local_vars, current_indent: current_indent)
          when "v2GetCharAt"
            source =
              if effect["sourceType"].to_s == "value"
                effect["source"].to_s
              else
                get_var(chat, effect["source"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            raw_index =
              if effect["indexType"].to_s == "value"
                effect["index"].to_s
              else
                get_var(chat, effect["index"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            index = safe_float(raw_index)
            out =
              if index.nan? || index.infinite? || !(index % 1).zero? || index.negative?
                "null"
              else
                ch = source[index.to_i]
                ch.nil? ? "null" : ch.to_s
              end

            set_var(chat, effect["outputVar"], out, local_vars: local_vars, current_indent: current_indent)
          when "v2GetCharCount"
            source =
              if effect["sourceType"].to_s == "value"
                effect["source"].to_s
              else
                get_var(chat, effect["source"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            set_var(chat, effect["outputVar"], source.length.to_s, local_vars: local_vars, current_indent: current_indent)
          when "v2ToLowerCase"
            source =
              if effect["sourceType"].to_s == "value"
                effect["source"].to_s
              else
                get_var(chat, effect["source"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            set_var(chat, effect["outputVar"], source.downcase, local_vars: local_vars, current_indent: current_indent)
          when "v2ToUpperCase"
            source =
              if effect["sourceType"].to_s == "value"
                effect["source"].to_s
              else
                get_var(chat, effect["source"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            set_var(chat, effect["outputVar"], source.upcase, local_vars: local_vars, current_indent: current_indent)
          when "v2SetCharAt"
            source =
              if effect["sourceType"].to_s == "value"
                effect["source"].to_s
              else
                get_var(chat, effect["source"], local_vars: local_vars, current_indent: current_indent).to_s
              end

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

            out =
              if index.nan? || index.infinite? || !(index % 1).zero? || index.negative?
                source
              else
                chars = source.chars
                chars[index.to_i] = value
                chars.join
              end

            set_var(chat, effect["outputVar"], out, local_vars: local_vars, current_indent: current_indent)
          when "v2ConcatString"
            s1 =
              if effect["source1Type"].to_s == "value"
                effect["source1"].to_s
              else
                get_var(chat, effect["source1"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            s2 =
              if effect["source2Type"].to_s == "value"
                effect["source2"].to_s
              else
                get_var(chat, effect["source2"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            set_var(chat, effect["outputVar"], s1 + s2, local_vars: local_vars, current_indent: current_indent)
          when "v2SplitString"
            source =
              if effect["sourceType"].to_s == "value"
                effect["source"].to_s
              else
                get_var(chat, effect["source"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            delimiter_type = effect["delimiterType"].to_s
            delimiter =
              case delimiter_type
              when "value"
                effect["delimiter"].to_s
              when "var"
                get_var(chat, effect["delimiter"], local_vars: local_vars, current_indent: current_indent).to_s
              else # regex
                effect["delimiter"].to_s
              end

            parts =
              if delimiter_type == "regex"
                begin
                  if (m = delimiter.match(%r{\A/(.+)/([gimuy]*)\z}))
                    pattern = m[1].to_s
                    flags = m[2].to_s
                    source.split(Regexp.new(pattern, regex_options(flags)))
                  else
                    source.split(Regexp.new(delimiter))
                  end
                rescue RegexpError
                  [source]
                end
              else
                source.split(delimiter)
              end

            set_var(chat, effect["outputVar"], ::JSON.generate(parts), local_vars: local_vars, current_indent: current_indent)
          when "v2JoinArrayVar"
            var_value =
              if effect["varType"].to_s == "value"
                effect["var"].to_s
              else
                get_var(chat, effect["var"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            delimiter =
              if effect["delimiterType"].to_s == "value"
                effect["delimiter"].to_s
              else
                get_var(chat, effect["delimiter"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            joined =
              begin
                arr = ::JSON.parse(var_value)
                Array(arr).join(delimiter)
              rescue JSON::ParserError, TypeError
                ""
              end

            set_var(chat, effect["outputVar"], joined, local_vars: local_vars, current_indent: current_indent)
          when "v2MakeDictVar", "v2ClearDict"
            var_name = effect["var"].to_s
            unless var_name.start_with?("{") && var_name.end_with?("}")
              set_var(chat, var_name, "{}", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2GetDictVar"
            var_value =
              if effect["varType"].to_s == "value"
                effect["var"].to_s
              else
                get_var(chat, effect["var"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            key =
              if effect["keyType"].to_s == "value"
                effect["key"].to_s
              else
                get_var(chat, effect["key"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            output_var = effect["outputVar"].to_s

            begin
              dict = ::JSON.parse(var_value)
              out = dict.is_a?(Hash) ? dict[key] : nil
              set_var(chat, output_var, out.nil? ? "null" : out.to_s, local_vars: local_vars, current_indent: current_indent)
            rescue JSON::ParserError, TypeError
              set_var(chat, output_var, "null", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2SetDictVar"
            next_value =
              if effect["valueType"].to_s == "value"
                effect["value"].to_s
              else
                get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            key =
              if effect["keyType"].to_s == "value"
                effect["key"].to_s
              else
                get_var(chat, effect["key"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            # v2SetDictVar cannot mutate dict literals (mirrors upstream).
            if effect["varType"].to_s != "value"
              var_name = effect["var"].to_s

              begin
                dict = ::JSON.parse(get_var(chat, var_name, local_vars: local_vars, current_indent: current_indent).to_s)
                dict = {} unless dict.is_a?(Hash)
                dict[key] = next_value
                set_var(chat, var_name, ::JSON.generate(dict), local_vars: local_vars, current_indent: current_indent)
              rescue JSON::ParserError, TypeError
                dict = { key => next_value }
                set_var(chat, var_name, ::JSON.generate(dict), local_vars: local_vars, current_indent: current_indent)
              end
            end
          when "v2DeleteDictKey"
            # v2DeleteDictKey cannot mutate dict literals (mirrors upstream).
            if effect["varType"].to_s != "value"
              var_name = effect["var"].to_s
              key =
                if effect["keyType"].to_s == "value"
                  effect["key"].to_s
                else
                  get_var(chat, effect["key"], local_vars: local_vars, current_indent: current_indent).to_s
                end

              begin
                dict = ::JSON.parse(get_var(chat, var_name, local_vars: local_vars, current_indent: current_indent).to_s)
                dict = {} unless dict.is_a?(Hash)
                dict.delete(key)
                set_var(chat, var_name, ::JSON.generate(dict), local_vars: local_vars, current_indent: current_indent)
              rescue JSON::ParserError, TypeError
                set_var(chat, var_name, "{}", local_vars: local_vars, current_indent: current_indent)
              end
            end
          when "v2HasDictKey"
            var_value =
              if effect["varType"].to_s == "value"
                effect["var"].to_s
              else
                get_var(chat, effect["var"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            key =
              if effect["keyType"].to_s == "value"
                effect["key"].to_s
              else
                get_var(chat, effect["key"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            output_var = effect["outputVar"].to_s

            begin
              dict = ::JSON.parse(var_value)
              hit = dict.is_a?(Hash) && dict.key?(key) ? "1" : "0"
              set_var(chat, output_var, hit, local_vars: local_vars, current_indent: current_indent)
            rescue JSON::ParserError, TypeError
              set_var(chat, output_var, "0", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2GetDictSize"
            var_value =
              if effect["varType"].to_s == "value"
                effect["var"].to_s
              else
                get_var(chat, effect["var"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            output_var = effect["outputVar"].to_s

            begin
              dict = ::JSON.parse(var_value)
              size = dict.is_a?(Hash) ? dict.size : 0
              set_var(chat, output_var, size.to_s, local_vars: local_vars, current_indent: current_indent)
            rescue JSON::ParserError, TypeError
              set_var(chat, output_var, "0", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2GetDictKeys"
            var_value =
              if effect["varType"].to_s == "value"
                effect["var"].to_s
              else
                get_var(chat, effect["var"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            output_var = effect["outputVar"].to_s

            begin
              dict = ::JSON.parse(var_value)
              keys = dict.is_a?(Hash) ? dict.keys : []
              set_var(chat, output_var, ::JSON.generate(keys), local_vars: local_vars, current_indent: current_indent)
            rescue JSON::ParserError, TypeError
              set_var(chat, output_var, "[]", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2GetDictValues"
            var_value =
              if effect["varType"].to_s == "value"
                effect["var"].to_s
              else
                get_var(chat, effect["var"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            output_var = effect["outputVar"].to_s

            begin
              dict = ::JSON.parse(var_value)
              values = dict.is_a?(Hash) ? dict.values : []
              set_var(chat, output_var, ::JSON.generate(values), local_vars: local_vars, current_indent: current_indent)
            rescue JSON::ParserError, TypeError
              set_var(chat, output_var, "[]", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2MakeArrayVar"
            var_name = effect["var"].to_s
            unless var_name.start_with?("[") && var_name.end_with?("]")
              set_var(chat, var_name, "[]", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2GetArrayVarLength"
            var_name = effect["var"].to_s
            output_var = effect["outputVar"].to_s

            length =
              begin
                arr = ::JSON.parse(get_var(chat, var_name, local_vars: local_vars, current_indent: current_indent).to_s)
                Array(arr).length
              rescue JSON::ParserError, TypeError
                0
              end

            set_var(chat, output_var, length.to_s, local_vars: local_vars, current_indent: current_indent)
          when "v2GetArrayVar"
            var_name = effect["var"].to_s
            raw_index =
              if effect["indexType"].to_s == "value"
                effect["index"].to_s
              else
                get_var(chat, effect["index"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            output_var = effect["outputVar"].to_s

            begin
              arr = Array(::JSON.parse(get_var(chat, var_name, local_vars: local_vars, current_indent: current_indent).to_s))
              idx = safe_float(raw_index)

              value =
                if idx.nan? || idx.infinite? || !(idx % 1).zero? || idx.negative?
                  nil
                else
                  arr[idx.to_i]
                end

              set_var(chat, output_var, value.nil? ? "null" : value.to_s, local_vars: local_vars, current_indent: current_indent)
            rescue JSON::ParserError, TypeError
              set_var(chat, output_var, "null", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2SetArrayVar"
            var_name = effect["var"].to_s
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

            idx = safe_float(raw_index)
            unless idx.nan? || idx.infinite? || !(idx % 1).zero? || idx.negative?
              begin
                arr = Array(::JSON.parse(get_var(chat, var_name, local_vars: local_vars, current_indent: current_indent).to_s))
                arr[idx.to_i] = value
                set_var(chat, var_name, ::JSON.generate(arr), local_vars: local_vars, current_indent: current_indent)
              rescue JSON::ParserError, TypeError
                nil
              end
            end
          when "v2PushArrayVar"
            var_name = effect["var"].to_s
            value =
              if effect["valueType"].to_s == "value"
                effect["value"].to_s
              else
                get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            begin
              arr = Array(::JSON.parse(get_var(chat, var_name, local_vars: local_vars, current_indent: current_indent).to_s))
              arr << value
              set_var(chat, var_name, ::JSON.generate(arr), local_vars: local_vars, current_indent: current_indent)
            rescue JSON::ParserError, TypeError
              set_var(chat, var_name, "[]", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2PopArrayVar"
            var_name = effect["var"].to_s
            output_var = effect["outputVar"].to_s

            begin
              arr = Array(::JSON.parse(get_var(chat, var_name, local_vars: local_vars, current_indent: current_indent).to_s))
              popped = arr.pop
              set_var(chat, output_var, popped.nil? ? "null" : popped.to_s, local_vars: local_vars, current_indent: current_indent)
              set_var(chat, var_name, ::JSON.generate(arr), local_vars: local_vars, current_indent: current_indent)
            rescue JSON::ParserError, TypeError
              set_var(chat, var_name, "[]", local_vars: local_vars, current_indent: current_indent)
              set_var(chat, output_var, "null", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2ShiftArrayVar"
            var_name = effect["var"].to_s
            output_var = effect["outputVar"].to_s

            begin
              arr = Array(::JSON.parse(get_var(chat, var_name, local_vars: local_vars, current_indent: current_indent).to_s))
              shifted = arr.shift
              set_var(chat, output_var, shifted.nil? ? "null" : shifted.to_s, local_vars: local_vars, current_indent: current_indent)
              set_var(chat, var_name, ::JSON.generate(arr), local_vars: local_vars, current_indent: current_indent)
            rescue JSON::ParserError, TypeError
              set_var(chat, var_name, "[]", local_vars: local_vars, current_indent: current_indent)
              set_var(chat, output_var, "null", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2UnshiftArrayVar"
            var_name = effect["var"].to_s
            value =
              if effect["valueType"].to_s == "value"
                effect["value"].to_s
              else
                get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            begin
              arr = Array(::JSON.parse(get_var(chat, var_name, local_vars: local_vars, current_indent: current_indent).to_s))
              arr.unshift(value)
              set_var(chat, var_name, ::JSON.generate(arr), local_vars: local_vars, current_indent: current_indent)
            rescue JSON::ParserError, TypeError
              set_var(chat, var_name, "[]", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2SpliceArrayVar"
            var_name = effect["var"].to_s
            raw_start =
              if effect["startType"].to_s == "value"
                effect["start"].to_s
              else
                get_var(chat, effect["start"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            item =
              if effect["itemType"].to_s == "value"
                effect["item"].to_s
              else
                get_var(chat, effect["item"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            begin
              arr = Array(::JSON.parse(get_var(chat, var_name, local_vars: local_vars, current_indent: current_indent).to_s))

              start = safe_float(raw_start)
              start_i = start.nan? || start.infinite? ? 0 : start.truncate
              start_i += arr.length if start_i.negative?
              start_i = 0 if start_i.negative?
              start_i = arr.length if start_i > arr.length

              arr.insert(start_i, item)
              set_var(chat, var_name, ::JSON.generate(arr), local_vars: local_vars, current_indent: current_indent)
            rescue JSON::ParserError, TypeError, FloatDomainError
              set_var(chat, var_name, "[]", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2SliceArrayVar"
            var_name = effect["var"].to_s
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

            output_var = effect["outputVar"].to_s

            begin
              arr = Array(::JSON.parse(get_var(chat, var_name, local_vars: local_vars, current_indent: current_indent).to_s))

              start = safe_float(raw_start)
              end_v = safe_float(raw_end)
              s_i = start.nan? || start.infinite? ? 0 : start.truncate
              e_i = end_v.nan? || end_v.infinite? ? 0 : end_v.truncate

              len = arr.length
              s_i += len if s_i.negative?
              e_i += len if e_i.negative?
              s_i = 0 if s_i.negative?
              e_i = 0 if e_i.negative?
              s_i = len if s_i > len
              e_i = len if e_i > len

              slice = arr[s_i...e_i] || []
              set_var(chat, output_var, ::JSON.generate(slice), local_vars: local_vars, current_indent: current_indent)
            rescue JSON::ParserError, TypeError, FloatDomainError
              set_var(chat, output_var, "[]", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2GetIndexOfValueInArrayVar"
            var_name = effect["var"].to_s
            value =
              if effect["valueType"].to_s == "value"
                effect["value"].to_s
              else
                get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            output_var = effect["outputVar"].to_s

            idx =
              begin
                arr = Array(::JSON.parse(get_var(chat, var_name, local_vars: local_vars, current_indent: current_indent).to_s))
                found = arr.index(value)
                found.nil? ? -1 : found
              rescue JSON::ParserError, TypeError
                -1
              end

            set_var(chat, output_var, idx.to_s, local_vars: local_vars, current_indent: current_indent)
          when "v2RemoveIndexFromArrayVar"
            var_name = effect["var"].to_s
            raw_index =
              if effect["indexType"].to_s == "value"
                effect["index"].to_s
              else
                get_var(chat, effect["index"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            begin
              arr = Array(::JSON.parse(get_var(chat, var_name, local_vars: local_vars, current_indent: current_indent).to_s))
              index = safe_float(raw_index)
              i = index.nan? || index.infinite? ? 0 : index.truncate
              i += arr.length if i.negative?
              i = 0 if i.negative?
              i = arr.length if i > arr.length
              arr.delete_at(i) if i < arr.length
              set_var(chat, var_name, ::JSON.generate(arr), local_vars: local_vars, current_indent: current_indent)
            rescue JSON::ParserError, TypeError, FloatDomainError
              set_var(chat, var_name, "[]", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2Calculate"
            expression =
              if effect["expressionType"].to_s == "value"
                effect["expression"].to_s
              else
                get_var(chat, effect["expression"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            expression = expression.gsub(/\$([a-zA-Z0-9_]+)/) do
              raw = get_var(chat, Regexp.last_match(1), local_vars: local_vars, current_indent: current_indent)
              num = parse_js_float_prefix(raw)
              num.nan? ? "0" : format_js_number(num)
            end

            result =
              begin
                v2_calc_string(expression)
              rescue StandardError
                0.0
              end

            set_var(
              chat,
              effect["outputVar"],
              format_js_number(result),
              local_vars: local_vars,
              current_indent: current_indent,
            )
          when "v2ReplaceString"
            source =
              if effect["sourceType"].to_s == "value"
                effect["source"].to_s
              else
                get_var(chat, effect["source"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            regex_pattern =
              if effect["regexType"].to_s == "value"
                effect["regex"].to_s
              else
                get_var(chat, effect["regex"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            result_format =
              if effect["resultType"].to_s == "value"
                effect["result"].to_s
              else
                get_var(chat, effect["result"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            replacement =
              if effect["replacementType"].to_s == "value"
                effect["replacement"].to_s
              else
                get_var(chat, effect["replacement"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            flags =
              if effect["flagsType"].to_s == "value"
                effect["flags"].to_s
              else
                get_var(chat, effect["flags"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            output_var = effect["outputVar"].to_s

            result =
              begin
                re = Regexp.new(regex_pattern, regex_options(flags))
                fn = ->(m) { v2_replace_string_replacement(m, result_format, replacement) }
                flags.include?("g") ? source.gsub(re) { fn.call(Regexp.last_match) } : source.sub(re) { fn.call(Regexp.last_match) }
              rescue StandardError
                source
              end

            set_var(chat, output_var, result, local_vars: local_vars, current_indent: current_indent)
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
            value =
              if effect["valueType"].to_s == "value"
                effect["value"].to_s
              else
                get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            depth_raw =
              if effect["depthType"].to_s == "value"
                effect["depth"].to_s
              else
                get_var(chat, effect["depth"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            depth = safe_float(depth_raw)
            output_var = effect["outputVar"].to_s
            if depth.nan?
              set_var(chat, output_var, "0", local_vars: local_vars, current_indent: current_indent)
            else
              messages = Array(chat[:message])
              slice_start = js_slice_index(-depth, messages.length)
              da = (messages[slice_start..] || []).map { |m| m.is_a?(Hash) ? m[:data].to_s : m.to_s }.join(" ")

              pass =
                case effect["condition"].to_s
                when "strict"
                  da.split(" ").include?(value)
                when "loose"
                  da.downcase.include?(value.downcase)
                when "regex"
                  begin
                    Regexp.new(value).match?(da)
                  rescue RegexpError
                    false
                  end
                else
                  false
                end

              set_var(chat, output_var, pass ? "1" : "0", local_vars: local_vars, current_indent: current_indent)
            end
          when "v2Tokenize"
            value =
              if effect["valueType"].to_s == "value"
                effect["value"].to_s
              else
                get_var(chat, effect["value"], local_vars: local_vars, current_indent: current_indent).to_s
              end

            estimator = chat[:token_estimator]
            estimator = TavernKit::TokenEstimator.default unless estimator&.respond_to?(:estimate)
            model_hint = chat[:model_hint]

            tokens =
              begin
                estimator.estimate(value, model_hint: model_hint).to_i
              rescue StandardError
                0
              end

            set_var(chat, effect["outputVar"], tokens.to_s, local_vars: local_vars, current_indent: current_indent)
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

      def numeric_equal?(a, b)
        na = safe_float(a)
        nb = safe_float(b)
        return a.to_s == b.to_s if na.nan? || nb.nan?

        na == nb
      end

      def approx_equal?(a, b)
        na = safe_float(a)
        nb = safe_float(b)

        if na.nan? || nb.nan?
          normalize = ->(v) { v.to_s.downcase.delete(" ") }
          return normalize.call(a) == normalize.call(b)
        end

        (na - nb).abs < 0.0001
      end

      def numeric_compare?(a, b, op)
        na = safe_float(a)
        nb = safe_float(b)
        return false if na.nan? || nb.nan?

        na.public_send(op, nb)
      end

      def safe_float(value)
        s = value.to_s.strip
        return Float::NAN if s == "NaN"
        return Float::INFINITY if s == "Infinity"
        return -Float::INFINITY if s == "-Infinity"

        Float(s)
      rescue ArgumentError, TypeError
        Float::NAN
      end

      # JS Array#slice index conversion (ToIntegerOrInfinity + bounds clamp).
      def js_slice_index(value, len)
        num = value.is_a?(Numeric) ? value.to_f : safe_float(value)
        inf = num.infinite?
        idx = inf ? (inf.positive? ? len : 0) : num.truncate

        if idx.negative?
          idx += len
          idx = 0 if idx.negative?
        elsif idx > len
          idx = len
        end

        idx
      end

      # Format a Float like JS `Number(...).toString()`:
      # - integer numbers render without ".0"
      # - NaN/Infinity render as their identifier strings
      def format_js_number(value)
        num = value.is_a?(Numeric) ? value.to_f : safe_float(value)
        return "NaN" if num.nan?

        inf = num.infinite?
        return inf.positive? ? "Infinity" : "-Infinity" if inf

        (num % 1).zero? ? num.to_i.to_s : num.to_s
      end

      def parse_js_float_prefix(value)
        s = value.to_s.lstrip
        return Float::NAN if s.empty?

        return Float::INFINITY if s.start_with?("Infinity")
        return -Float::INFINITY if s.start_with?("-Infinity")
        return Float::NAN if s.start_with?("NaN")

        m = s.match(/\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/)
        return Float::NAN unless m

        safe_float(m[0])
      end
      private_class_method :parse_js_float_prefix

      def v2_calc_string(expr)
        tokens = v2_calc_tokenize(expr)
        rpn = v2_calc_to_rpn(tokens)
        v2_calc_eval_rpn(rpn)
      end
      private_class_method :v2_calc_string

      def v2_calc_tokenize(expr)
        s = expr.to_s.gsub(/\s+/, "")
        tokens = []

        i = 0
        while i < s.length
          ch = s[i]

          if ch == "(" || ch == ")"
            tokens << ch
            i += 1
            next
          end

          if "+-*/%^".include?(ch)
            if ch == "-" && (tokens.empty? || tokens.last.is_a?(String) && tokens.last != ")")
              # Unary minus becomes part of the number token.
              j = i + 1
              j += 1 while j < s.length && s[j] =~ /[0-9.]/
              if j < s.length && s[j] =~ /[eE]/
                k = j + 1
                k += 1 if k < s.length && s[k] =~ /[+-]/
                k += 1 while k < s.length && s[k] =~ /\d/
                j = k
              end

              tokens << safe_float(s[i...j])
              i = j
            else
              tokens << ch
              i += 1
            end
            next
          end

          if ch =~ /[0-9.]/
            j = i
            j += 1 while j < s.length && s[j] =~ /[0-9.]/
            if j < s.length && s[j] =~ /[eE]/
              k = j + 1
              k += 1 if k < s.length && s[k] =~ /[+-]/
              k += 1 while k < s.length && s[k] =~ /\d/
              j = k
            end

            tokens << safe_float(s[i...j])
            i = j
            next
          end

          raise ArgumentError, "Unexpected token: #{ch}"
        end

        tokens
      end
      private_class_method :v2_calc_tokenize

      def v2_calc_to_rpn(tokens)
        prec = { "+" => 2, "-" => 2, "*" => 3, "/" => 3, "%" => 3, "^" => 4 }.freeze

        out = []
        ops = []

        tokens.each do |t|
          if t.is_a?(Numeric)
            out << t
            next
          end

          if t == "("
            ops << t
            next
          end

          if t == ")"
            out << ops.pop while ops.any? && ops.last != "("
            ops.pop if ops.last == "("
            next
          end

          # operator
          while ops.any? && ops.last != "(" && prec.fetch(ops.last) >= prec.fetch(t)
            out << ops.pop
          end
          ops << t
        end

        out.concat(ops.reverse.reject { |op| op == "(" })
        out
      end
      private_class_method :v2_calc_to_rpn

      def v2_calc_eval_rpn(rpn)
        stack = []

        rpn.each do |t|
          if t.is_a?(Numeric)
            stack << t
            next
          end

          b = stack.pop || Float::NAN
          a = stack.pop || Float::NAN

          stack <<
            case t
            when "+"
              a + b
            when "-"
              a - b
            when "*"
              a * b
            when "/"
              a / b
            when "%"
              b.zero? ? Float::NAN : (a % b)
            when "^"
              a**b
            else
              Float::NAN
            end
        end

        stack.pop || 0.0
      rescue ZeroDivisionError, FloatDomainError
        Float::NAN
      end
      private_class_method :v2_calc_eval_rpn

      def equivalent?(a, b)
        tv = b.to_s
        sv = a.to_s

        if tv == "true"
          sv == "true" || sv == "1"
        elsif tv == "false"
          !(sv == "true" || sv == "1")
        else
          sv == tv
        end
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

        re = Regexp.new(pattern, regex_options(flags))
        match = re.match(text)
        return unless match

        result = out.gsub(/\$\d+/) do |m|
          idx = Integer(m.delete_prefix("$"), exception: false)
          idx && match[idx] ? match[idx].to_s : ""
        end
        result = result.gsub("$&", match[0].to_s)
        result = result.gsub("$$", "$")

        set_var(chat, input_var, result, local_vars: local_vars, current_indent: current_indent)
      rescue RegexpError
        nil
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

      def get_var(chat, name, local_vars:, current_indent:)
        key = name.to_s.delete_prefix("$")
        if local_vars
          local = local_vars.get(key, current_indent: current_indent)
          return local unless local.nil?
        end

        if (store = chat[:variables])
          if store.respond_to?(:get)
            value = store.get(key, scope: :local)
            return value unless value.nil?
          end
        end

        state = chat[:scriptstate]
        return nil unless state.is_a?(Hash)

        state["$#{key}"]
      end

      def set_var(chat, name, value, local_vars:, current_indent:)
        key = name.to_s.delete_prefix("$")

        if local_vars && !local_vars.get(key, current_indent: current_indent).nil?
          local_vars.set(key, value, indent: current_indent)
          return
        end

        if (store = chat[:variables])
          store.set(key, value.to_s, scope: :local) if store.respond_to?(:set)
        end

        state = chat[:scriptstate]
        return unless state.is_a?(Hash) || store.nil?

        state ||= {}
        state["$#{key}"] = value.to_s
        chat[:scriptstate] = state
      end

      def deep_symbolize(value)
        case value
        when Array
          value.map { |v| deep_symbolize(v) }
        when Hash
          value.each_with_object({}) do |(k, v), out|
            if k.is_a?(String) && k.start_with?("$")
              out[k] = deep_symbolize(v)
            else
              out[k.to_sym] = deep_symbolize(v)
            end
          end
        else
          value
        end
      end

      def normalize_triggers(triggers)
        Array(triggers).filter_map do |raw|
          next nil unless raw.is_a?(Hash)

          TavernKit::Utils.deep_stringify_keys(raw)
        end
      end
      private_class_method :normalize_triggers
    end
  end
end
