# frozen_string_literal: true

module TavernKit
  module RisuAI
    # Internal helper methods for the trigger engine.
    #
    # Pure refactor: extracted from `risu_ai/triggers.rb` to keep file sizes
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
