# frozen_string_literal: true

module TavernKit
  module RisuAI
    # RisuAI trigger engine (Wave 5f).
    #
    # This starts with the v1-style trigger schema used by characterization
    # tests (conditions + effect array). v2 effects are added iteratively.
    module Triggers
      Result = Data.define(:chat)

      module_function

      def run(trigger, chat:)
        t = TavernKit::Utils.deep_stringify_keys(trigger.is_a?(Hash) ? trigger : {})
        c = deep_symbolize(chat.is_a?(Hash) ? chat : {})

        type = t.fetch("type", "").to_s
        # Characterization tests call run() directly, so we don't filter by mode here.
        _ = type

        conditions = Array(t["conditions"]).select { |v| v.is_a?(Hash) }
        effects = Array(t["effect"]).select { |v| v.is_a?(Hash) }

        return Result.new(chat: c) unless conditions_pass?(conditions, chat: c)

        effects.each do |effect|
          apply_effect(effect, chat: c)
        end

        Result.new(chat: c)
      end

      def conditions_pass?(conditions, chat:)
        conditions.all? do |condition|
          case condition["type"].to_s
          when "var", "chatindex", "value"
            check_var_condition(condition, chat: chat)
          when "exists"
            check_exists_condition(condition, chat: chat)
          else
            false
          end
        end
      end

      def check_var_condition(condition, chat:)
        var_value =
          case condition["type"].to_s
          when "var"
            get_var(chat, condition["var"]) || "null"
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

      def apply_effect(effect, chat:)
        case effect["type"].to_s
        when "setvar"
          apply_setvar(effect, chat: chat)
        when "v2If", "v2IfAdvanced", "v2SetVar", "v2EndIndent"
          # v2 is implemented iteratively; ignored for now until tests unskip.
          nil
        else
          nil
        end
      end

      def apply_setvar(effect, chat:)
        key = effect["var"].to_s
        value = effect["value"].to_s
        operator = effect["operator"].to_s

        original = get_var(chat, key).to_f
        original = 0 if original.nan?

        result =
          case operator
          when "="
            value
          when "+="
            (original + value.to_f).to_s
          when "-="
            (original - value.to_f).to_s
          when "*="
            (original * value.to_f).to_s
          when "/="
            (original / value.to_f).to_s
          when "%="
            (original % value.to_f).to_s
          else
            value
          end

        set_var(chat, key, result)
      end

      def get_var(chat, name)
        key = name.to_s
        key = "$#{key}" unless key.start_with?("$")
        chat[:scriptstate] ||= {}
        chat[:scriptstate][key]
      end

      def set_var(chat, name, value)
        key = name.to_s
        key = "$#{key}" unless key.start_with?("$")

        chat[:scriptstate] ||= {}
        chat[:scriptstate][key] = value.to_s
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
    end
  end
end
