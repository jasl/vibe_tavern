# frozen_string_literal: true

require_relative "macros/time_macros"
require_relative "macros/logic_macros"
require_relative "macros/collection_macros"
require_relative "macros/string_macros"

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
          when "chatindex"
            resolve_chatindex(environment)
          when "messageindex"
            resolve_messageindex(environment)
          when "personality", "charpersona"
            resolve_personality(environment)
          when "description", "chardesc"
            resolve_description(environment)
          when "scenario"
            resolve_scenario(environment)
          when "exampledialogue", "examplemessage"
            resolve_exampledialogue(environment)
          when "persona", "userpersona"
            resolve_persona(environment)
          when "date", "datetimeformat"
            resolve_date(args)
          when "time"
            resolve_time(args)
          when "unixtime"
            resolve_unixtime
          when "isotime"
            resolve_isotime
          when "isodate"
            resolve_isodate
          when "model"
            resolve_model(environment)
          when "role"
            resolve_role(environment)
          when "metadata"
            resolve_metadata(args, environment: environment)
          when "iserror"
            resolve_iserror(args)
          when "equal"
            resolve_equal(args)
          when "notequal"
            resolve_notequal(args)
          when "greater"
            resolve_greater(args)
          when "less"
            resolve_less(args)
          when "greaterequal"
            resolve_greaterequal(args)
          when "lessequal"
            resolve_lessequal(args)
          when "and"
            resolve_and(args)
          when "or"
            resolve_or(args)
          when "not"
            resolve_not(args)
          when "all"
            resolve_all(args)
          when "any"
            resolve_any(args)
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
          when "hash"
            resolve_hash(args)
          when "pick"
            resolve_pick(args, environment: environment)
          when "random"
            resolve_random(args)
          when "randint"
            resolve_randint(args)
          when "dice"
            resolve_dice(args)
          when "roll"
            resolve_roll(args)
          when "rollp", "rollpick"
            resolve_rollp(args, environment: environment)
          when "arrayelement"
            resolve_arrayelement(args)
          when "dictelement", "objectelement"
            resolve_dictelement(args)
          when "objectassert", "dictassert"
            resolve_objectassert(args)
          when "element", "ele"
            resolve_element(args)
          when "arrayshift"
            resolve_arrayshift(args)
          when "arraypop"
            resolve_arraypop(args)
          when "arraypush"
            resolve_arraypush(args)
          when "arraysplice"
            resolve_arraysplice(args)
          when "arrayassert"
            resolve_arrayassert(args)
          when "makearray", "array", "a"
            resolve_makearray(args)
          when "makedict", "dict", "d", "makeobject", "object", "o"
            resolve_makedict(args)
          when "range"
            resolve_range(args)
          when "filter"
            resolve_filter(args)
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

        def resolve_chatindex(environment)
          (environment.respond_to?(:chat_index) ? (environment.chat_index || -1) : -1).to_i.to_s
        end
        private_class_method :resolve_chatindex

        def resolve_messageindex(environment)
          (environment.respond_to?(:message_index) ? (environment.message_index || 0) : 0).to_i.to_s
        end
        private_class_method :resolve_messageindex

        def resolve_personality(environment)
          char = environment.respond_to?(:character) ? environment.character : nil
          text = char&.respond_to?(:data) ? char.data&.personality.to_s : ""
          render_nested(text, environment: environment)
        end
        private_class_method :resolve_personality

        def resolve_description(environment)
          char = environment.respond_to?(:character) ? environment.character : nil
          text = char&.respond_to?(:data) ? char.data&.description.to_s : ""
          render_nested(text, environment: environment)
        end
        private_class_method :resolve_description

        def resolve_scenario(environment)
          char = environment.respond_to?(:character) ? environment.character : nil
          text = char&.respond_to?(:data) ? char.data&.scenario.to_s : ""
          render_nested(text, environment: environment)
        end
        private_class_method :resolve_scenario

        def resolve_exampledialogue(environment)
          char = environment.respond_to?(:character) ? environment.character : nil
          text = char&.respond_to?(:data) ? char.data&.mes_example.to_s : ""
          render_nested(text, environment: environment)
        end
        private_class_method :resolve_exampledialogue

        def resolve_persona(environment)
          user = environment.respond_to?(:user) ? environment.user : nil
          text = user&.respond_to?(:persona_text) ? user.persona_text.to_s : environment.user_name.to_s
          render_nested(text, environment: environment)
        end
        private_class_method :resolve_persona

        def resolve_model(environment)
          environment.respond_to?(:model_hint) ? environment.model_hint.to_s : ""
        end
        private_class_method :resolve_model

        def resolve_role(environment)
          role =
            if environment.respond_to?(:role)
              environment.role
            else
              nil
            end
          role.nil? ? "null" : role.to_s
        end
        private_class_method :resolve_role

        def resolve_metadata(args, environment:)
          key_raw = args[0].to_s
          key = normalize_name(key_raw)

          metadata =
            if environment.respond_to?(:metadata)
              environment.metadata
            else
              nil
            end

          unless metadata.is_a?(Hash) && metadata.key?(key)
            return "Error: #{key_raw} is not a valid metadata key."
          end

          value = metadata[key]
          return value ? "1" : "0" if value == true || value == false

          value.is_a?(Hash) || value.is_a?(Array) ? ::JSON.generate(value) : value.to_s
        end
        private_class_method :resolve_metadata

        def resolve_iserror(args)
          args[0].to_s.downcase.start_with?("error:") ? "1" : "0"
        end
        private_class_method :resolve_iserror

        def resolve_getvar(args, environment:)
          name = args[0].to_s
          value = environment.get_var(name, scope: :local)
          value.nil? ? "null" : value.to_s
        rescue NotImplementedError
          "null"
        end
        private_class_method :resolve_getvar

        def resolve_getglobalvar(args, environment:)
          name = args[0].to_s
          value = environment.get_var(name, scope: :global)
          value.nil? ? "null" : value.to_s
        rescue NotImplementedError
          "null"
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
          current = environment.get_var(name, scope: :local)
          current_s = current.nil? ? "null" : current.to_s
          environment.set_var(name, value, scope: :local) if current_s.empty?
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

          current = environment.get_var(name, scope: :local)
          current_s = current.nil? ? "null" : current.to_s

          sum = js_number(current_s) + js_number(delta)
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

        def resolve_hash(args)
          word = args[0].to_s
          num = (TavernKit::RisuAI::Utils.pick_hash_rand(0, word) * 10_000_000) + 1
          num.round.to_i.to_s.rjust(7, "0")
        end
        private_class_method :resolve_hash

        def resolve_pick(args, environment:)
          cid = deterministic_cid(environment)
          rand = TavernKit::RisuAI::Utils.pick_hash_rand(cid, deterministic_word(environment))
          random_pick_impl(args, rand: rand)
        end
        private_class_method :resolve_pick

        def resolve_random(args)
          random_pick_impl(args, rand: Random.rand)
        end
        private_class_method :resolve_random

        def resolve_randint(args)
          min = parse_js_number(args[0])
          max = parse_js_number(args[1])
          return "NaN" if min.is_a?(String) || max.is_a?(String)

          format_number((Random.rand * (max - min + 1)).floor + min)
        rescue StandardError
          "NaN"
        end
        private_class_method :resolve_randint

        def resolve_dice(args)
          notation = args[0].to_s.split("d")
          num = parse_js_number(notation[0])
          sides = parse_js_number(notation[1])
          return "NaN" if num.is_a?(String) || sides.is_a?(String)

          count = num.ceil
          count = 0 if count.negative?

          total = 0
          count.times { total += (Random.rand * sides).floor + 1 }
          total.to_s
        rescue StandardError
          "NaN"
        end
        private_class_method :resolve_dice

        def resolve_roll(args)
          return "1" if args.empty?

          notation = args[0].to_s.split("d")
          num = 1.0
          sides = 6.0

          if notation.length == 2
            num = notation[0].to_s.empty? ? 1.0 : Float(notation[0])
            sides = notation[1].to_s.empty? ? 6.0 : Float(notation[1])
          elsif notation.length == 1
            sides = Float(notation[0])
          end

          return "NaN" if num.nan? || sides.nan?
          return "NaN" if num < 1 || sides < 1

          total = 0
          count = num.ceil
          count.times { total += (Random.rand * sides).floor + 1 }
          total.to_s
        rescue ArgumentError, TypeError
          "NaN"
        end
        private_class_method :resolve_roll

        def resolve_rollp(args, environment:)
          return "1" if args.empty?

          notation = args[0].to_s.split("d")
          num = 1.0
          sides = 6.0

          if notation.length == 2
            num = notation[0].to_s.empty? ? 1.0 : Float(notation[0])
            sides = notation[1].to_s.empty? ? 6.0 : Float(notation[1])
          elsif notation.length == 1
            sides = Float(notation[0])
          end

          return "NaN" if num.nan? || sides.nan?
          return "NaN" if num < 1 || sides < 1

          total = 0
          count = num.ceil
          base = deterministic_cid(environment)
          word = deterministic_word(environment)

          count.times do |i|
            cid = base + (i * 15)
            rand = TavernKit::RisuAI::Utils.pick_hash_rand(cid, word)
            total += (rand * sides).floor + 1
          end

          total.to_s
        rescue ArgumentError, TypeError
          "NaN"
        end
        private_class_method :resolve_rollp

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

        def resolve_arraylength(args)
          parse_cbs_array(args[0]).length.to_s
        end
        private_class_method :resolve_arraylength

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

        def render_nested(text, environment:)
          TavernKit::RisuAI::CBS::Engine.new.expand(text.to_s, environment: environment)
        end
        private_class_method :render_nested

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

        def random_pick_impl(args, rand:)
          return rand.to_s if args.empty?

          arr =
            if args.length == 1
              parsed = parse_pick_array(args[0])
              parsed.nil? ? split_pick_args(args[0]) : parsed
            else
              args
            end

          return "" if arr.empty?

          index = (rand * arr.length).floor
          element = arr[index]

          if element.is_a?(String)
            element.gsub("§X", ",")
          else
            ::JSON.generate(element) || ""
          end
        end
        private_class_method :random_pick_impl

        def parse_pick_array(value)
          s = value.to_s
          return nil unless s.start_with?("[") && s.end_with?("]")

          arr = ::JSON.parse(s)
          arr.is_a?(Array) ? arr : nil
        rescue ::JSON::ParserError
          nil
        end
        private_class_method :parse_pick_array

        def split_pick_args(value)
          value.to_s.gsub("\\,", "§X").split(/[:\,]/)
        end
        private_class_method :split_pick_args

        def deterministic_cid(environment)
          (environment.respond_to?(:message_index) ? (environment.message_index || 0) : 0).to_i
        end
        private_class_method :deterministic_cid

        def deterministic_word(environment)
          word =
            if environment.respond_to?(:rng_word)
              environment.rng_word.to_s
            else
              ""
            end

          return word unless word.empty?

          if environment.respond_to?(:character_name)
            fallback = environment.character_name.to_s
            return fallback unless fallback.empty?
          end

          "0"
        end
        private_class_method :deterministic_word

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

        def js_number(value)
          return Float::NAN if value.nil?

          s = value.to_s
          return 0.0 if s.strip.empty?

          Float(s)
        rescue ArgumentError, TypeError
          Float::NAN
        end
        private_class_method :js_number
      end
    end
  end
end
