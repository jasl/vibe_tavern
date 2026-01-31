# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      # Small subset of the CBS macro registry (Wave 5b).
      #
      # Upstream reference:
      # resources/Risuai/src/ts/cbs.ts (registerFunction)
      module Macros
        module_function

        def resolve(name, args, environment:)
          key = normalize_name(name)

          case key
          when "char", "bot"
            resolve_char(environment)
          when "user"
            resolve_user(environment)
          when "prefillsupported", "prefill"
            resolve_prefill_supported(environment)
          when "getvar"
            resolve_getvar(args, environment: environment)
          when "setvar"
            resolve_setvar(args, environment: environment)
          when "addvar"
            resolve_addvar(args, environment: environment)
          when "setdefaultvar"
            resolve_setdefaultvar(args, environment: environment)
          when "getglobalvar"
            resolve_getglobalvar(args, environment: environment)
          when "tempvar", "gettempvar"
            resolve_tempvar(args, environment: environment)
          when "settempvar"
            resolve_settempvar(args, environment: environment)
          when "return"
            resolve_return(args, environment: environment)
          when "startswith"
            resolve_startswith(args)
          when "endswith"
            resolve_endswith(args)
          when "contains"
            resolve_contains(args)
          when "replace"
            resolve_replace(args)
          when "split"
            resolve_split(args)
          when "join"
            resolve_join(args)
          when "spread"
            resolve_spread(args)
          when "tonumber"
            resolve_tonumber(args)
          when "pow"
            resolve_pow(args)
          when "arrayelement"
            resolve_arrayelement(args)
          when "trim"
            resolve_trim(args)
          when "length"
            resolve_length(args)
          when "arraylength"
            resolve_arraylength(args)
          when "lower"
            resolve_lower(args)
          when "upper"
            resolve_upper(args)
          when "capitalize"
            resolve_capitalize(args)
          when "round"
            resolve_round(args)
          when "floor"
            resolve_floor(args)
          when "ceil"
            resolve_ceil(args)
          when "abs"
            resolve_abs(args)
          when "remaind"
            resolve_remaind(args)
          else
            nil
          end
        end

        def normalize_name(name)
          name.to_s.downcase.gsub(/[\s_-]+/, "")
        end
        private_class_method :normalize_name

        def resolve_char(environment)
          char = environment.respond_to?(:character) ? environment.character : nil
          return environment.character_name.to_s if char.nil?

          if char.respond_to?(:display_name)
            char.display_name.to_s
          elsif char.respond_to?(:name)
            char.name.to_s
          else
            environment.character_name.to_s
          end
        end
        private_class_method :resolve_char

        def resolve_user(environment)
          user = environment.respond_to?(:user) ? environment.user : nil
          return environment.user_name.to_s if user.nil?

          user.respond_to?(:name) ? user.name.to_s : environment.user_name.to_s
        end
        private_class_method :resolve_user

        def resolve_prefill_supported(environment)
          # Upstream checks for Claude models (db.aiModel.startsWith('claude')) and
          # returns "1"/"0". TavernKit approximates this using dialect/model_hint.
          dialect = environment.respond_to?(:dialect) ? environment.dialect : nil
          model_hint = environment.respond_to?(:model_hint) ? environment.model_hint.to_s : ""

          supported =
            dialect.to_s == "anthropic" ||
            model_hint.downcase.start_with?("claude") ||
            model_hint.downcase.include?("claude-")

          supported ? "1" : "0"
        end
        private_class_method :resolve_prefill_supported

        def resolve_getvar(args, environment:)
          name = args[0].to_s
          environment.get_var(name, scope: :local).to_s
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_getvar

        def resolve_getglobalvar(args, environment:)
          name = args[0].to_s
          environment.get_var(name, scope: :global).to_s
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_getglobalvar

        def resolve_setvar(args, environment:)
          return "" if rm_var?(environment)
          return nil unless run_var?(environment)

          name = args[0].to_s
          value = args[1].to_s
          environment.set_var(name, value, scope: :local)
          ""
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_setvar

        def resolve_setdefaultvar(args, environment:)
          return "" if rm_var?(environment)
          return nil unless run_var?(environment)

          name = args[0].to_s
          value = args[1].to_s
          current = environment.get_var(name, scope: :local).to_s
          environment.set_var(name, value, scope: :local) if current.empty?
          ""
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_setdefaultvar

        def resolve_addvar(args, environment:)
          return "" if rm_var?(environment)
          return nil unless run_var?(environment)

          name = args[0].to_s
          delta = args[1].to_s

          current = environment.get_var(name, scope: :local).to_s
          sum = current.to_f + delta.to_f
          environment.set_var(name, format_number(sum), scope: :local)
          ""
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_addvar

        def resolve_tempvar(args, environment:)
          name = args[0].to_s
          environment.get_var(name, scope: :temp).to_s
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_tempvar

        def resolve_settempvar(args, environment:)
          name = args[0].to_s
          value = args[1].to_s
          environment.set_var(name, value, scope: :temp)
          ""
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_settempvar

        def resolve_return(args, environment:)
          environment.set_var("__return__", args[0], scope: :temp)
          environment.set_var("__force_return__", "1", scope: :temp)
          ""
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_return

        def resolve_startswith(args)
          args[0].to_s.start_with?(args[1].to_s) ? "1" : "0"
        end
        private_class_method :resolve_startswith

        def resolve_endswith(args)
          args[0].to_s.end_with?(args[1].to_s) ? "1" : "0"
        end
        private_class_method :resolve_endswith

        def resolve_contains(args)
          args[0].to_s.include?(args[1].to_s) ? "1" : "0"
        end
        private_class_method :resolve_contains

        def resolve_replace(args)
          args[0].to_s.gsub(args[1].to_s, args[2].to_s)
        end
        private_class_method :resolve_replace

        def resolve_split(args)
          delimiter = args[1].to_s
          make_array(args[0].to_s.split(delimiter))
        end
        private_class_method :resolve_split

        def resolve_join(args)
          list = parse_cbs_array(args[0])
          delimiter = args[1].to_s
          list.map { |v| v.is_a?(String) ? v : ::JSON.generate(v) }.join(delimiter)
        end
        private_class_method :resolve_join

        def resolve_spread(args)
          list = parse_cbs_array(args[0])
          list.map { |v| v.is_a?(String) ? v : ::JSON.generate(v) }.join("::")
        end
        private_class_method :resolve_spread

        def resolve_tonumber(args)
          args[0].to_s.each_char.filter_map do |ch|
            if ch == "." || ch.match?(/\A\d\z/) || ch.match?(/\A\s\z/)
              ch
            end
          end.join
        end
        private_class_method :resolve_tonumber

        def resolve_pow(args)
          a = parse_js_number(args[0])
          b = parse_js_number(args[1])
          return "NaN" if a.is_a?(String) || b.is_a?(String)
          return "NaN" if a.negative? && (b % 1) != 0

          format_number(a**b)
        rescue StandardError
          "NaN"
        end
        private_class_method :resolve_pow

        def resolve_arrayelement(args)
          list = parse_cbs_array(args[0])
          index = args[1].to_s.to_i
          element = list[index]
          return "null" if element.nil?

          element.is_a?(Hash) || element.is_a?(Array) ? ::JSON.generate(element) : element.to_s
        rescue StandardError
          "null"
        end
        private_class_method :resolve_arrayelement

        def resolve_trim(args)
          args[0].to_s.strip
        end
        private_class_method :resolve_trim

        def resolve_length(args)
          args[0].to_s.length.to_s
        end
        private_class_method :resolve_length

        def resolve_arraylength(args)
          parse_cbs_array(args[0]).length.to_s
        end
        private_class_method :resolve_arraylength

        def resolve_lower(args)
          args[0].to_s.downcase
        end
        private_class_method :resolve_lower

        def resolve_upper(args)
          args[0].to_s.upcase
        end
        private_class_method :resolve_upper

        def resolve_capitalize(args)
          s = args[0].to_s
          return "" if s.empty?

          s[0].upcase + s[1..].to_s
        end
        private_class_method :resolve_capitalize

        def resolve_round(args)
          v = parse_js_number(args[0])
          return v if v.is_a?(String)

          ((v + 0.5).floor).to_s
        end
        private_class_method :resolve_round

        def resolve_floor(args)
          v = parse_js_number(args[0])
          return v if v.is_a?(String)

          v.floor.to_s
        end
        private_class_method :resolve_floor

        def resolve_ceil(args)
          v = parse_js_number(args[0])
          return v if v.is_a?(String)

          v.ceil.to_s
        end
        private_class_method :resolve_ceil

        def resolve_abs(args)
          v = parse_js_number(args[0])
          return v.sub("-", "") if v.is_a?(String) && v.start_with?("-Infinity")
          return v if v.is_a?(String)

          format_number(v.abs)
        end
        private_class_method :resolve_abs

        def resolve_remaind(args)
          a = parse_js_number(args[0])
          b = parse_js_number(args[1])
          return "NaN" if a.is_a?(String) || b.is_a?(String)
          return "NaN" if b.zero?

          format_number(a % b)
        rescue ZeroDivisionError
          "NaN"
        end
        private_class_method :resolve_remaind

        def parse_js_number(value)
          s = value.to_s.strip
          return 0.0 if s.empty?

          f = Float(s)
          return f.to_s if f.nan?
          return f.to_s if f.infinite?

          f
        rescue ArgumentError, TypeError
          "NaN"
        end
        private_class_method :parse_js_number

        def parse_cbs_array(value)
          s = value.to_s

          begin
            arr = ::JSON.parse(s)
            return arr if arr.is_a?(Array)
          rescue ::JSON::ParserError
            nil
          end

          s.split("§")
        end
        private_class_method :parse_cbs_array

        def make_array(array)
          ::JSON.generate(
            Array(array).map do |v|
              v.is_a?(String) ? v.gsub("::", "\\u003A\\u003A") : v
            end,
          )
        end
        private_class_method :make_array

        def run_var?(environment)
          environment.respond_to?(:run_var) && environment.run_var == true
        end
        private_class_method :run_var?

        def rm_var?(environment)
          environment.respond_to?(:rm_var) && environment.rm_var == true
        end
        private_class_method :rm_var?

        def format_number(value)
          v = value.is_a?(Numeric) ? value : value.to_f
          (v.to_f % 1).zero? ? v.to_i.to_s : v.to_f.to_s
        end
        private_class_method :format_number
      end
    end
  end
end
