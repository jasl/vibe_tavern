# frozen_string_literal: true

module TavernKit
  module RisuAI
    # V2 effect implementations for string/regex/math-ish operations.
    #
    # Pure refactor: extracted from `risu_ai/triggers.rb` (Wave 6 large-file split).
    module Triggers
      module_function

      def apply_v2_random(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_regex_test(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_extract_regex(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_get_char_at(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_get_char_count(effect, chat:, local_vars:, current_indent:)
        source =
          if effect["sourceType"].to_s == "value"
            effect["source"].to_s
          else
            get_var(chat, effect["source"], local_vars: local_vars, current_indent: current_indent).to_s
          end

        set_var(chat, effect["outputVar"], source.length.to_s, local_vars: local_vars, current_indent: current_indent)
      end

      def apply_v2_to_lower_case(effect, chat:, local_vars:, current_indent:)
        source =
          if effect["sourceType"].to_s == "value"
            effect["source"].to_s
          else
            get_var(chat, effect["source"], local_vars: local_vars, current_indent: current_indent).to_s
          end

        set_var(chat, effect["outputVar"], source.downcase, local_vars: local_vars, current_indent: current_indent)
      end

      def apply_v2_to_upper_case(effect, chat:, local_vars:, current_indent:)
        source =
          if effect["sourceType"].to_s == "value"
            effect["source"].to_s
          else
            get_var(chat, effect["source"], local_vars: local_vars, current_indent: current_indent).to_s
          end

        set_var(chat, effect["outputVar"], source.upcase, local_vars: local_vars, current_indent: current_indent)
      end

      def apply_v2_set_char_at(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_concat_string(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_split_string(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_join_array_var(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_calculate(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_replace_string(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_quick_search_chat(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_tokenize(effect, chat:, local_vars:, current_indent:)
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
      end
    end
  end
end
