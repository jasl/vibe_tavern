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
        idx = 0
        mode = trigger["type"].to_s
        current_indent = 0
        loop_n_times = Hash.new(0)

        while idx < effects.length
          effect = effects[idx]
          type = effect["type"].to_s
          unless effect_allowed?(type, mode: mode)
            idx += 1
            next
          end

          indent_value = Integer(effect["indent"].to_s, exception: false)
          current_indent = indent_value && indent_value >= 0 ? indent_value : 0

          case type
          when "v2IfAdvanced"
            indent = Integer(effect["indent"].to_s, exception: false) || 0
            pass = v2_if_pass?(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)

            unless pass
              # Skip until the matching end of this indent block.
              end_indent = indent + 1
              idx += 1
              while idx < effects.length
                ef = effects[idx]
                if ef["type"].to_s == "v2EndIndent" && (Integer(ef["indent"].to_s, exception: false) || 0) == end_indent
                  # If there's an else clause, jump to it so the loop increment
                  # lands on the first else-body effect.
                  next_ef = effects[idx + 1]
                  if next_ef.is_a?(Hash) && next_ef["type"].to_s == "v2Else" && (Integer(next_ef["indent"].to_s, exception: false) || 0) == indent
                    idx += 1
                  end
                  break
                end

                idx += 1
              end
            end
          when "v2SetVar"
            apply_v2_setvar(effect, chat: chat, local_vars: local_vars, current_indent: current_indent)
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
            idx += 1
            while idx < effects.length
              ef = effects[idx]
              break if ef["type"].to_s == "v2EndIndent" && (Integer(ef["indent"].to_s, exception: false) || 0) == end_indent

              idx += 1
            end
          when "v2EndIndent"
            end_indent = Integer(effect["indent"].to_s, exception: false) || 0

            if effect["endOfLoop"] == true
              loop_indent = end_indent - 1
              original_idx = idx

              header_idx = nil
              scan = idx
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
                      idx = header_idx
                    else
                      idx = original_idx
                    end
                  else
                    idx = header_idx
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
            scan = idx
            while scan < effects.length
              ef = effects[scan]
              if ef["type"].to_s == "v2EndIndent" && ef["endOfLoop"] == true
                idx = scan
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

          idx += 1
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
        Float(value)
      rescue ArgumentError, TypeError
        Float::NAN
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
