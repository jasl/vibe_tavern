# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Triggers
      # Trigger condition evaluation (v1 schema).
      #
      # Pure refactor: extracted from `risu_ai/triggers.rb` to keep file sizes
      # manageable (Wave 6 large-file split).

      module_function

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
          re = TavernKit::RegexSafety.compile(val)
          re ? TavernKit::RegexSafety.match?(re, da) : false
        else
          false
        end
      end
    end
  end
end
