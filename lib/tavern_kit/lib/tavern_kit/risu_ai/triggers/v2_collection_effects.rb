# frozen_string_literal: true

module TavernKit
  module RisuAI
    # V2 effect implementations for dict/array variable operations (JSON-backed).
    #
    # Pure refactor: extracted from `risu_ai/triggers.rb` (Wave 6 large-file split).
    module Triggers
      module_function

      def apply_v2_make_dict_var(effect, chat:, local_vars:, current_indent:)
        var_name = effect["var"].to_s
        unless var_name.start_with?("{") && var_name.end_with?("}")
          set_var(chat, var_name, "{}", local_vars: local_vars, current_indent: current_indent)
        end
      end

      def apply_v2_get_dict_var(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_set_dict_var(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_delete_dict_key(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_has_dict_key(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_get_dict_size(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_get_dict_keys(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_get_dict_values(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_make_array_var(effect, chat:, local_vars:, current_indent:)
        var_name = effect["var"].to_s
        unless var_name.start_with?("[") && var_name.end_with?("]")
          set_var(chat, var_name, "[]", local_vars: local_vars, current_indent: current_indent)
        end
      end

      def apply_v2_get_array_var_length(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_get_array_var(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_set_array_var(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_push_array_var(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_pop_array_var(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_shift_array_var(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_unshift_array_var(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_splice_array_var(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_slice_array_var(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_get_index_of_value_in_array_var(effect, chat:, local_vars:, current_indent:)
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
      end

      def apply_v2_remove_index_from_array_var(effect, chat:, local_vars:, current_indent:)
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
      end
    end
  end
end

