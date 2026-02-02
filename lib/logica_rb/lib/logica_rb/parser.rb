# frozen_string_literal: true

require "json"
require "stringio"
require "set"

require_relative "common/color"
require_relative "util"

module LogicaRb
  module Parser
    extend self

    CLOSE_TO_OPEN = {
      ")" => "(",
      "}" => "{",
      "]" => "[",
    }.freeze
    CLOSING_PARENTHESIS = CLOSE_TO_OPEN.keys.freeze
    OPENING_PARENTHESIS = CLOSE_TO_OPEN.values.freeze
    VARIABLE_CHARS_SET = Set.new(("a".."z").to_a + ["_"] + ("0".."9").to_a).freeze
    @too_much = "too much"

    def too_much
      @too_much
    end

    class HeritageAwareString < String
      attr_accessor :start_pos, :stop_pos, :heritage

      def initialize(content)
        super(content.to_s)
        @start_pos = 0
        @stop_pos = length
        @heritage = to_s
      end

      def [](slice_or_index, slice_length = nil)
        if slice_length.nil?
          if slice_or_index.is_a?(Integer)
            return HeritageAwareString.new(super(slice_or_index))
          elsif slice_or_index.is_a?(Range)
            start = slice_or_index.begin || 0
            stop = slice_or_index.end
            if stop
              if stop < 0
                stop = length + stop
              end
              stop += 1 unless slice_or_index.exclude_end?
            end
            return get_slice(start, stop)
          end
          return HeritageAwareString.new(super(slice_or_index))
        end
        get_slice(slice_or_index, slice_or_index + slice_length)
      end

      def get_slice(start_idx, stop_idx)
        start_idx = length + start_idx if start_idx && start_idx < 0
        stop_idx = length if stop_idx.nil? || stop_idx > length
        stop_idx = length + stop_idx if stop_idx && stop_idx < 0
        substring = HeritageAwareString.new(to_s[start_idx...stop_idx] || "")
        substring.start_pos = @start_pos + start_idx
        substring.stop_pos = @start_pos + stop_idx
        substring.heritage = @heritage
        substring
      end

      def pieces
        [@heritage[0...@start_pos], @heritage[@start_pos...@stop_pos], @heritage[@stop_pos..]]
      end

      def display
        before, error, after = pieces
        error = "<EMPTY>" if error.nil? || error.empty?
        LogicaRb::Common::Color.format(
          "{before}{warning}{error_text}{end}{after}",
          { before: before, error_text: error, after: after }
        )
      end
    end

    class ParsingException < StandardError
      attr_reader :location

      def initialize(message, location)
        message = message.gsub(">>", LogicaRb::Common::Color.color("warning")).gsub("<<", LogicaRb::Common::Color.color("end"))
        super(message)
        @location = location
      end

      def show_message(stream = $stderr)
        stream.puts(LogicaRb::Common::Color.format("{underline}Parsing{end}:"))
        before, error, after = @location.pieces
        before = before[-300..] if before && before.length > 300
        after = after[0, 300] if after && after.length > 300
        error = "<EMPTY>" if error.nil? || error.empty?
        stream.puts(LogicaRb::Common::Color.format("{before}{warning}{error_text}{end}{after}",
                                                   { before: before, error_text: error, after: after }))
        stream.puts(LogicaRb::Common::Color.format("\n[ {error}Error{end} ] ") + message)
      end
    end

    def enact_incantations(main_code)
      if main_code.include?("Signa inter verba conjugo, symbolum infixus evoco!")
        @too_much = "fun"
      end
    end

    def functor_syntax_error_message
      "Incorrect syntax for functor call. Functor call to be made as\n" \
        "  R := F(A: V, ...)\n" \
        "or\n" \
        "  @Make(R, F, {A: V, ...})\n" \
        "Where R, F, A's and V's are all predicate names."
    end

    def traverse(s)
      Enumerator.new do |y|
        state = ""
        state_char = lambda { state.empty? ? "" : state[-1] }

        idx = -1
        while idx + 1 < s.length
          idx += 1
          c = s[idx]
          c2 = s[idx, 2]
          c3 = s[idx, 3]

          track_parenthesis = true

        case state_char.call
        when "#"
          track_parenthesis = false
          if c == "\n"
            state = state[0...-1]
          else
            next
          end
        when '"'
          track_parenthesis = false
          if c == "\n"
            y << [idx, nil, "EOL in string"]
            next
          end
          state = state[0...-1] if c == '"'
        when "'"
          track_parenthesis = false
          state = state[0...-1] if c == "'"
          state += "\\" if c == "\\"
        when "\\"
          state = state[0...-1]
        when "`"
          track_parenthesis = false
          state = state[0...-1] if c == "`"
        when "3"
          track_parenthesis = false
          if c3 == '"""'
            state = state[0...-1]
            y << [idx, state, "OK"]
            idx += 1
            y << [idx, state, "OK"]
            idx += 1
            next
          end
        when "/"
          track_parenthesis = false
          if c2 == "*/"
            state = state[0...-1]
            idx += 1
          end
          next
        else
          if c == "#"
            state += "#"
            next
          elsif c3 == '"""'
            state += "3"
            y << [idx, state, "OK"]
            idx += 1
            y << [idx, state, "OK"]
            idx += 1
            next
          elsif c == '"'
            state += '"'
          elsif c == "'"
            state += "'"
          elsif c == "`"
            state += "`"
          elsif c2 == "/*"
            state += "/"
            idx += 1
            next
          end
        end

        if track_parenthesis
          if OPENING_PARENTHESIS.include?(c)
            state += c
          elsif CLOSING_PARENTHESIS.include?(c)
            if !state.empty? && state[-1] == CLOSE_TO_OPEN[c]
              state = state[0...-1]
            else
              y << [idx, nil, "Unmatched"]
              break
            end
          end
        end
        y << [idx, state, "OK"]
        end
      end
    end

      def remove_comments(s)
        chars = []
        traverse(s).each do |idx, _state, status|
          case status
          when "Unmatched"
            raise ParsingException.new("Parenthesis matches nothing.", s[idx, 1])
          when "EOL in string"
            raise ParsingException.new("End of line in string.", s[idx, 0])
          else
            chars << s[idx]
          end
        end
        chars.join
      end

      def is_whole(s)
        status = "OK"
        state = ""
        traverse(s).each do |_idx, st, st_status|
          state = st
          status = st_status
        end
        status == "OK" && state == ""
      end

      def show_traverse(s)
        traverse(s).map { |idx, state, status| [idx, s[idx], state, status] }
      end

      def strip(s)
        loop do
          s = strip_spaces(s)
          if s.length >= 2 && s[0] == "(" && s[-1] == ")" && is_whole(s[1..-2])
            s = s[1..-2]
          else
            return s
          end
        end
      end

      def strip_spaces(s)
        s = HeritageAwareString.new(s) unless s.is_a?(HeritageAwareString)
        left_idx = 0
        right_idx = s.length - 1
        while left_idx < s.length && s[left_idx].match?(/\s/)
          left_idx += 1
        end
        while right_idx > left_idx && s[right_idx].match?(/\s/)
          right_idx -= 1
        end
        s.get_slice(left_idx, right_idx + 1)
      end

      def split_raw(s, separator)
        s = HeritageAwareString.new(s) unless s.is_a?(HeritageAwareString)
        parts = []
        l = separator.length
        enum = traverse(s).to_enum
        part_start = 0
        separator_alphanum = separator.match?(/\A[[:alnum:]]+\z/)
        loop do
          idx, state, status = enum.next
          raise ParsingException.new("Parenthesis matches nothing.", s[idx, 1]) if status != "OK"
          if state == "" && s[idx, l] == separator &&
              (s.length == idx + l || s[idx + l] != "|") &&
              (idx == 0 || s[idx - 1] != "|")
            if separator_alphanum
              if (idx > 0 && s[idx - 1].match?(/[[:alnum:]]/)) ||
                  (idx + l < s.length && s[idx + l].match?(/[[:alnum:]]/))
                next
              end
            end
            parts << s.get_slice(part_start, idx)
            (l - 1).times { idx, _state, _status = enum.next }
            part_start = idx + 1
          end
        rescue StopIteration
          break
        end
        parts << s.get_slice(part_start, s.length)
        parts
      end

      def split(s, separator)
        split_raw(s, separator).map { |p| strip(p) }
      end

      def split_in_two(s, separator)
        parts = split(s, separator)
        raise ParsingException.new("I expected string to be split by >>#{separator}<< in two.", s) unless parts.length == 2

        [parts[0], parts[1]]
      end

      def split_in_one_or_two(s, separator)
        parts = split(s, separator)
        if parts.length == 1
          [[parts[0]], nil]
        elsif parts.length == 2
          [nil, [parts[0], parts[1]]]
        else
          raise ParsingException.new(
            "String should have been split by >>#{separator}<< in 1 or 2 pieces.", s
          )
        end
      end

      def split_many(ss, separator)
        result = []
        ss.each { |x| result.concat(split(x, separator)) }
        result
      end

      def split_on_whitespace(s)
        ss = [s]
        " \n\t".each_char { |sep| ss = split_many(ss, sep) }
        ss.reject { |chunk| chunk.nil? || chunk.empty? }
      end

      # Parsing functions.
      def parse_record(s)
        s = strip(s)
        if s.length >= 2 && s[0] == "{" && s[-1] == "}" && is_whole(s[1..-2])
          return parse_record_internals(s[1..-2], is_record_literal: true)
        end
        nil
      end

      def parse_record_internals(s, is_record_literal: false, is_aggregation_allowed: false)
        s = strip(s)
        if split(s, ":-").length > 1
          raise ParsingException.new(
            "Unexpected >>:-<< in record internals. " \
            "If you apply a function to a >>combine<< statement, place it in " \
            "auxiliary variable first.",
            s
          )
        end
        return { "field_value" => [] } if s.nil? || s.empty?

        result = []
        if is_whole(s)
          field_values = split(s, ",")
          had_restof = false
          positional_ok = true
          observed_fields = []
          field_values.each_with_index do |field_value, idx|
            if had_restof
              raise ParsingException.new("Field >>..<rest_of><< must go last.", field_value)
            end
            if field_value.start_with?("..")
              if is_record_literal
                raise ParsingException.new("Field >>..<rest_of> in record literals<< is not currently suppported .", field_value)
              end
              item = {
                "field" => "*",
                "value" => { "expression" => parse_expression(field_value[2..]) },
              }
              item["except"] = observed_fields if observed_fields.any?
              result << item
              had_restof = true
              positional_ok = false
              next
            end
            (_no_split, colon_split) = split_in_one_or_two(field_value, ":")
            if colon_split
              positional_ok = false
              field, value = colon_split

              observed_field = field
              if value.nil? || value.empty?
                value = field
                if field && field[0].match?(/[A-Z]/)
                  raise ParsingException.new(
                    'Record fields may not start with capital letter, as it is reserved for predicate literals.\n' \
                    'Backtick the field name if you need it capitalized. E.g. "Q(`A`: 1)".',
                    field
                  )
                end

                if field && field[0] == "`"
                  raise ParsingException.new(
                    "Backticks in variable names are disallowed. Please give an explicit variable for the value of the column.",
                    field
                  )
                end
              end

              result << {
                "field" => field,
                "value" => { "expression" => parse_expression(value) },
              }
            else
              (_no_split2, question_split) = split_in_one_or_two(field_value, "?")
              if question_split
                if !is_aggregation_allowed
                  raise ParsingException.new("Aggregation of fields is only allowed in the head of a rule.", field_value)
                end
                positional_ok = false
                field, value = question_split
                observed_field = field
                if field.nil? || field.empty?
                  raise ParsingException.new("Aggregated fields have to be named.", field_value)
                end
                operator, expression = split_in_two(value, "=")
                operator = strip(operator)
                result << {
                  "field" => field,
                  "value" => {
                    "aggregation" => {
                      "operator" => operator,
                      "argument" => parse_expression(expression),
                      "expression_heritage" => value,
                    },
                  },
                }
              else
                if positional_ok
                  result << {
                    "field" => idx,
                    "value" => { "expression" => parse_expression(field_value) },
                  }
                  observed_field = "col#{idx}"
                else
                  raise ParsingException.new(
                    "Positional argument can not go after non-positional arguments.", field_value
                  )
                end
              end
            end
            observed_fields << observed_field
          end
        end

        { "field_value" => result }
      end

      def parse_variable(s)
        if s && s[0] && s[0].match?(/[a-z_]/) && s.chars.all? { |ch| VARIABLE_CHARS_SET.include?(ch) }
          if s.start_with?("x_")
            raise ParsingException.new(
              "Variables starting with >>x_<< are reserved to be Logica compiler internal. Please use a different name.",
              s
            )
          end
          return { "var_name" => s }
        end
        nil
      end

      def parse_number(s)
        s = s[0..-2] if s[-1] == "u"
        return { "number" => "-1" } if s == "∞"
        begin
          Float(s)
        rescue ArgumentError
          return nil
        end
        { "number" => s }
      end

      def parse_python_single_quoted(str)
        return nil unless str.start_with?("'") && str.end_with?("'")
        body = str[1..-2]
        result = +""
        i = 0
        while i < body.length
          ch = body[i]
          if ch == "\\"
            i += 1
            return nil if i >= body.length
            esc = body[i]
            case esc
            when "n" then result << "\n"
            when "t" then result << "\t"
            when "r" then result << "\r"
            when "b" then result << "\b"
            when "f" then result << "\f"
            when "a" then result << "\a"
            when "v" then result << "\v"
            when "\\" then result << "\\"
            when "'" then result << "'"
            when '"' then result << '"'
            when "x"
              hex = body[(i + 1)..(i + 2)]
              return nil unless hex && hex.length == 2 && hex.match?(/\A[0-9a-fA-F]{2}\z/)
              result << hex.to_i(16).chr(Encoding::UTF_8)
              i += 2
            when "u"
              hex = body[(i + 1)..(i + 4)]
              return nil unless hex && hex.length == 4 && hex.match?(/\A[0-9a-fA-F]{4}\z/)
              result << hex.to_i(16).chr(Encoding::UTF_8)
              i += 4
            when "U"
              hex = body[(i + 1)..(i + 8)]
              return nil unless hex && hex.length == 8 && hex.match?(/\A[0-9a-fA-F]{8}\z/)
              codepoint = hex.to_i(16)
              result << [codepoint].pack("U")
              i += 8
            when "\n"
              # Line continuation, ignore.
            else
              if esc.match?(/[0-7]/)
                oct = esc
                j = i + 1
                while j < body.length && body[j].match?(/[0-7]/) && oct.length < 3
                  oct << body[j]
                  j += 1
                end
                result << oct.to_i(8).chr(Encoding::UTF_8)
                i = j - 1
              else
                result << esc
              end
            end
          else
            result << ch
          end
          i += 1
        end
        result
      end

      def parse_string(s)
        if s.length >= 2 && s[0] == '"' && s[-1] == '"' && !s[1..-2].include?('"')
          return { "the_string" => s[1..-2] }
        end
        if s.length >= 2 && s[0] == "'" && s[-1] == "'"
          meat = s[1..-2]
          screen = false
          valid = true
          meat.each_char do |c|
            if screen
              screen = false
              next
            end
            if c == "'"
              valid = false
              break
            end
            screen = true if c == "\\"
          end
          if valid
            parsed = parse_python_single_quoted(s)
            return { "the_string" => parsed } if parsed
          end
        end
        if s.length >= 6 && s.start_with?('"""') && s.end_with?('"""') && !s[3..-4].include?('"""')
          return { "the_string" => s[3..-4] }
        end
        nil
      end

      def parse_boolean(s)
        return { "the_bool" => s } if %w[true false].include?(s)
        nil
      end

      def parse_null(s)
        return { "the_null" => s } if s == "null"
        nil
      end

      def parse_list(s)
        if s.length >= 2 && s[0] == "[" && s[-1] == "]" && is_whole(s[1..-2])
          inside = strip(s[1..-2])
          if inside.nil? || inside.empty?
            elements = []
          else
            elements_str = split(inside, ",")
            elements = elements_str.map { |e| parse_expression(e) }
          end
          return { "element" => elements }
        end
        nil
      end

      def parse_predicate_literal(s)
        if s == "++?" || s == "nil" ||
            (!s.empty? && s.chars.all? { |ch| ch.match?(/[A-Za-z0-9_]/) } && s[0].match?(/[A-Z]/))
          return { "predicate_name" => s }
        end
        nil
      end

      def parse_literal(s)
        v = parse_number(s)
        return { "the_number" => v } if v
        v = parse_string(s)
        return { "the_string" => v } if v
        v = parse_list(s)
        return { "the_list" => v } if v
        v = parse_boolean(s)
        return { "the_bool" => v } if v
        v = parse_null(s)
        return { "the_null" => v } if v
        v = parse_predicate_literal(s)
        return { "the_predicate" => v } if v
        nil
      end

      def parse_infix(s, operators: nil, disallow_operators: nil)
        if too_much == "fun"
          user_defined_operators = ["---", "-+-", "-*-", "-/-", "-%-", "-^-",
                                    "\u25C7", "\u25CB", "\u2661", "\u2295", "\u2297"]
        else
          user_defined_operators = []
        end
        operators ||= (user_defined_operators + [
          "||", "&&", "->", "==", "<=", ">=", "<", ">", "!=", "=", "~",
          " in ", " is not ", " is ", "++?", "++", "+", "-", "*", "/", "%",
          "^", "!",
        ])
        disallow_operators ||= []
        unary_operators = ["-", "!"]
        operators.each do |op|
          next if disallow_operators.include?(op)
          parts = split_raw(s, op)
          if parts.length > 1
            left_len = parts[-2].stop_pos - s.start_pos
            right_start = parts[-1].start_pos - s.start_pos
            left = strip(s[0...left_len])
            right = strip(s[right_start..-1])
            if op == "~" && left.length > 0 && left[-1] == "!"
              next
            end
            if unary_operators.include?(op) && left.empty?
              return {
                "predicate_name" => op,
                "record" => parse_record_internals(right),
              }
            end
            return nil if op == "~" && left.empty?

            left_expr = parse_expression(left)
            right_expr = parse_expression(right)
            return {
              "predicate_name" => op.strip,
              "record" => {
                "field_value" => [
                  { "field" => "left", "value" => { "expression" => left_expr } },
                  { "field" => "right", "value" => { "expression" => right_expr } },
                ],
              },
            }
          end
        end
        nil
      end

      def build_tree_for_combine(parsed_expression, operator, parsed_body, full_text)
        aggregated_field_value = {
          "field" => "logica_value",
          "value" => {
            "aggregation" => {
              "operator" => operator,
              "argument" => parsed_expression,
              "expression_heritage" => full_text,
            },
          },
        }
        result = {
          "head" => {
            "predicate_name" => "Combine",
            "record" => { "field_value" => [aggregated_field_value] },
          },
          "distinct_denoted" => true,
          "full_text" => full_text,
        }
        result["body"] = { "conjunction" => parsed_body } if parsed_body
        result
      end

      def parse_combine(s)
        return nil unless s.start_with?("combine ")
        s = s["combine ".length..]
        (_no_split, value_body) = split_in_one_or_two(s, ":-")
        if value_body
          value, body = value_body
        else
          value = s
          body = nil
        end
        operator, expression = split_in_two(value, "=")
        operator = strip(operator)
        parsed_expression = parse_expression(expression)
        parsed_body = body ? parse_conjunction(body, allow_singleton: true) : nil
        build_tree_for_combine(parsed_expression, operator, parsed_body, s)
      end

      def parse_concise_combine(s)
        parts = split(s, "=")
        return nil unless parts.length == 2
        lhs_and_op, combine = parts
        left_parts = split_on_whitespace(lhs_and_op)
        return nil unless left_parts.length > 1
        lhs = s[0...left_parts[-2].stop_pos - s.start_pos]
        operator = left_parts[-1]
        prohibited_operators = ["!", "<", ">"]
        return nil if prohibited_operators.include?(operator)
        return nil if operator[0].match?(/[a-z]/)
        left_expr = parse_expression(lhs)
        (_no_split, expression_body) = split_in_one_or_two(combine, ":-")
        if expression_body
          expression, body = expression_body
        else
          expression = combine
          body = nil
        end
        parsed_expression = parse_expression(expression)
        parsed_body = body ? parse_conjunction(body, allow_singleton: true) : nil
        right_expr = build_tree_for_combine(parsed_expression, operator, parsed_body, s)
        {
          "left_hand_side" => left_expr,
          "right_hand_side" => { "combine" => right_expr, "expression_heritage" => s },
        }
      end

      def parse_implication(s)
        return nil unless s.start_with?("if ") || s.start_with?("if\n")
        inner = s[3..]
        if_thens = split(inner, "else if")
        last_if_then, last_else = split_in_two(if_thens[-1], "else")
        if_thens[-1] = last_if_then
        result_if_thens = []
        if_thens.each do |condition_consequence|
          condition, consequence = split_in_two(condition_consequence, "then")
          result_if_thens << {
            "condition" => parse_expression(condition),
            "consequence" => parse_expression(consequence),
          }
        end
        last_else_parsed = parse_expression(last_else)
        { "if_then" => result_if_thens, "otherwise" => last_else_parsed }
      end

      def parse_ultra_concise_combine(s)
        aggregation_call = parse_generic_call(s, "{", "}")
        return nil unless aggregation_call
        aggregating_function, multiset_rule_str = aggregation_call
        (_no_split, value_body) = split_in_one_or_two(multiset_rule_str, ":-")
        if value_body
          value, body = value_body
        else
          value = multiset_rule_str
          body = nil
        end
        parsed_expression = parse_expression(value)
        parsed_body = body ? parse_conjunction(body, allow_singleton: true) : nil
        build_tree_for_combine(parsed_expression, aggregating_function, parsed_body, s)
      end

      def parse_expression(s)
        e = actually_parse_expression(s)
        e["expression_heritage"] = s
        e
      end

      def actually_parse_expression(s)
        v = parse_combine(s)
        return { "combine" => v } if v
        v = parse_implication(s)
        return { "implication" => v } if v
        v = parse_literal(s)
        return { "literal" => v } if v
        v = parse_variable(s)
        return { "variable" => v } if v
        v = parse_record(s)
        return { "record" => v } if v
        v = parse_propositional_implication(s)
        return { "call" => v["predicate"] } if v
        v = parse_call(s, is_aggregation_allowed: false)
        return { "call" => v } if v
        v = parse_ultra_concise_combine(s)
        return { "combine" => v } if v
        v = parse_infix(s, disallow_operators: ["~"])
        return { "call" => v } if v
        v = parse_subscript(s)
        return { "subscript" => v } if v
        v = parse_negation_expression(s)
        return v if v
        v = parse_array_sub(s)
        return { "call" => v } if v
        raise ParsingException.new("Could not parse expression of a value.", s)
      end

      def parse_inclusion(s)
        element_list_str = split(s, " in ")
        return nil unless element_list_str.length == 2
        { "list" => parse_expression(element_list_str[1]), "element" => parse_expression(element_list_str[0]) }
      end

      def parse_generic_call(s, opening, closing)
        s = strip(s)
        predicate = ""
        idx = 0
        return nil if s.nil? || s.empty?
        if s.start_with?("->")
          idx = 2
          predicate = "->"
        else
          traverse(s).each do |i, state, status|
            raise ParsingException.new("Parenthesis matches nothing.", s[i, 1]) if status != "OK"
            if state == opening
              good_chars = Set.new(("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a +
                                   ["@", "_", ".", "$", "{", "}", "+", "-", "`"])
              if too_much == "fun"
                good_chars.merge(["*", "^", "%", "/", "\u25C7", "\u25CB", "\u2661", "\u2295", "\u2297"])
              end
              if (i > 0 && s[0...i].chars.all? { |c| good_chars.include?(c) }) ||
                  s[0...i] == "!" || s[0...i] == "++?" ||
                  (i >= 2 && s[0] == "`" && s[i - 1] == "`")
                predicate = s[0...i]
                idx = i
                break
              else
                return nil
              end
            end
            if !state.empty? && state != "{" && state[0] != "`"
              return nil
            end
          end
          return nil if predicate.empty?
        end
        if s[idx] == opening && s[-1] == closing && is_whole(s[(idx + 1)..-2])
          predicate = "=" if predicate == "`=`"
          predicate = "~" if predicate == "`~`"
          return [predicate, s[(idx + 1)...-1]]
        end
        nil
      end

      def parse_call(s, is_aggregation_allowed:)
        generic_parse = parse_generic_call(s, "(", ")")
        return nil if generic_parse.nil?
        caller, args_str = generic_parse
        args = parse_record_internals(args_str, is_aggregation_allowed: is_aggregation_allowed)
        { "predicate_name" => caller, "record" => args }
      end

      def parse_array_sub(s)
        generic_parse = parse_generic_call(s, "[", "]")
        return nil if generic_parse.nil?
        caller, args_str = generic_parse
        args = parse_record_internals(args_str, is_aggregation_allowed: false)
        array = parse_expression(caller)
        nested_element(s, array, args)
      end

      def nested_element(s, array, args)
        result = nil
        args["field_value"].each_with_index do |fv, _i|
          fv = LogicaRb::Util.deep_copy(fv)
          if fv["field"] != _i
            raise ParsingException.new(
              "Array subscription must only have positional arguments. Non positional argument: >>%s<<" % fv["field"], s
            )
          end
          fv["field"] = 1
          first_argument = result.nil? ? array : { "call" => result }
          element_args = {
            "field_value" => [
              { "field" => 0, "value" => { "expression" => first_argument } },
              fv,
            ],
          }
          result = { "predicate_name" => "Element", "record" => element_args }
        end
        result
      end

      def parse_unification(s)
        parts = split(s, "==")
        return nil unless parts.length == 2
        left, right = parts
        left_expr = parse_expression(left)
        right_expr = parse_expression(right)
        { "left_hand_side" => left_expr, "right_hand_side" => right_expr }
      end

      def parse_proposition(s)
        c = parse_disjunction(s)
        return { "disjunction" => c } if c
        str_conjuncts = split(s, ",")
        c = parse_conjunction(s, allow_singleton: false)
        return { "conjunction" => c } if str_conjuncts.length > 1
        if too_much == "fun"
          c = parse_propositional_equivalence(s)
          return { "conjunction" => { "conjunct" => [c] } } if c
        end
        c = parse_propositional_implication(s)
        return c if c
        c = parse_implication(s)
        raise ParsingException.new("If-then-else clause is only supported as an expression, not as a proposition.", s) if c
        c = parse_call(s, is_aggregation_allowed: false)
        return { "predicate" => c } if c
        c = parse_infix(s, operators: ["&&", "||"])
        return { "predicate" => c } if c
        c = parse_unification(s)
        return { "unification" => c } if c
        c = parse_inclusion(s)
        return { "inclusion" => c } if c
        c = parse_concise_combine(s)
        return { "unification" => c } if c
        c = parse_infix(s)
        return { "predicate" => c } if c
        c = parse_negation(s)
        return c if c
        raise ParsingException.new("Could not parse proposition.", s)
      end

      def parse_conjunction(s, allow_singleton: false)
        str_conjuncts = split(s, ",")
        return nil if str_conjuncts.length == 1 && !allow_singleton
        conjuncts = str_conjuncts.map { |c| parse_proposition(c) }
        { "conjunct" => conjuncts }
      end

      def parse_disjunction(s)
        str_disjuncts = split(s, "|")
        return nil if str_disjuncts.length == 1
        disjuncts = str_disjuncts.map { |d| parse_proposition(d) }
        { "disjunct" => disjuncts }
      end

      def parse_propositional_implication(s)
        str_implicants = split(s, "=>")
        return nil unless str_implicants.length == 2
        condition_str, consequence_str = str_implicants
        condition = parse_proposition(condition_str)
        consequence = parse_proposition(consequence_str)
        propositional_implication(s, str_implicants[1], condition, consequence)
      end

      def propositional_implication(s, consequence_str, condition, consequence)
        ensure_conjunction = lambda do |x|
          return x if x.key?("conjunction")
          { "conjunction" => { "conjunct" => [x] } }
        end
        conjuncts = if condition.key?("conjunction")
                      condition["conjunction"]["conjunct"]
        else
                      [condition]
        end
        conjuncts += [negation_tree(consequence_str, ensure_conjunction.call(consequence))]
        negation_tree(s, { "conjunction" => { "conjunct" => conjuncts } })
      end

      def parse_propositional_equivalence(s)
        str_equivalents = split(s, "<=>")
        return nil unless str_equivalents.length == 2
        left_str, right_str = str_equivalents
        left1 = parse_proposition(left_str)
        right1 = parse_proposition(right_str)
        left2 = parse_proposition(left_str)
        right2 = parse_proposition(right_str)
        { "conjunction" => { "conjunct" => [
          propositional_implication(s, right_str, left1, right1),
          propositional_implication(s, left_str, right2, left2),
        ] } }
      end

      def parse_negation_expression(s)
        proposition = parse_negation(s)
        return nil unless proposition
        { "call" => proposition["predicate"] }
      end

      def parse_negation(s)
        space_and_negated = split(s, "~")
        return nil if space_and_negated.length == 1
        if space_and_negated.length != 2 || !space_and_negated[0].empty?
          raise ParsingException.new('Negation "~" is a unary operator.', s)
        end
        _space, negated = space_and_negated
        negated = strip(negated)
        negated_proposition = { "conjunction" => parse_conjunction(negated, allow_singleton: true) }
        negation_tree(s, negated_proposition)
      end

      def negation_tree(s, negated_proposition)
        number_one = { "literal" => { "the_number" => { "number" => "1" } } }
        {
          "predicate" => {
            "predicate_name" => "IsNull",
            "record" => {
              "field_value" => [
                {
                  "field" => 0,
                  "value" => {
                    "expression" => {
                      "combine" => {
                        "body" => negated_proposition,
                        "distinct_denoted" => true,
                        "full_text" => s,
                        "head" => {
                          "predicate_name" => "Combine",
                          "record" => {
                            "field_value" => [
                              {
                                "field" => "logica_value",
                                "value" => {
                                  "aggregation" => {
                                    "operator" => "Min",
                                    "argument" => number_one,
                                    "expression_heritage" => s,
                                  },
                                },
                              },
                            ],
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        }
      end

      def parse_subscript(s)
        str_path = split_raw(s, ".")
        return nil unless str_path.length >= 2
        record_str = s[0...(str_path[-2].stop_pos - s.start_pos)]
        record_str_doublecheck = str_path[0...-1].map(&:to_s).join(".")
        raise "This should not happen." unless record_str == record_str_doublecheck
        record = parse_expression(strip(record_str))
        unless str_path[-1].chars.all? { |ch| ch.match?(/[a-z0-9_]/) }
          raise ParsingException.new("Subscript must be lowercase.", s)
        end
        subscript = { "literal" => { "the_symbol" => { "symbol" => str_path[-1] } } }
        { "record" => record, "subscript" => subscript }
      end

      def parse_head_call(s, distinct_from_outside: false)
        saw_open = false
        idx = -1
        traverse(s).each do |i, state, status|
          raise ParsingException.new("Parenthesis matches nothing.", s[i, 1]) if status != "OK"
          saw_open = true if state == "("
          if saw_open && state.empty?
            idx = i
            break
          end
        end
        raise ParsingException.new("Found no call in rule head.", s) if idx < 0

        call_str = s[0..idx]
        post_call_str = s[(idx + 1)..]
        call = parse_call(call_str, is_aggregation_allowed: true)
        raise ParsingException.new("Could not parse predicate call.", call_str) unless call

        operator_expression = split(post_call_str, "=")
        check_aggregation_coherence = lambda do |call_node|
          return if distinct_from_outside
          call_node["record"]["field_value"].each do |fv|
            if fv["value"].key?("aggregation")
              raise ParsingException.new(
                "Aggregation appears in a non-distinct predicate. Did you forget >>distinct<<?",
                call_str
              )
            end
          end
        end

        if operator_expression.length == 1
          raise ParsingException.new("Unexpected text in the head of a rule.", operator_expression[0]) if operator_expression[0] && !operator_expression[0].empty?
          check_aggregation_coherence.call(call)
          return [call, false]
        end
        if operator_expression.length > 2
          raise ParsingException.new("Too many '=' in predicate value.", post_call_str)
        end

        operator_str, expression_str = operator_expression
        if operator_str.nil? || operator_str.empty?
          call["record"]["field_value"] << {
            "field" => "logica_value",
            "value" => { "expression" => parse_expression(expression_str) },
          }
          check_aggregation_coherence.call(call)
          return [call, false]
        end

        aggregated_field_value = {
          "field" => "logica_value",
          "value" => {
            "aggregation" => {
              "operator" => operator_str,
              "argument" => parse_expression(expression_str),
              "expression_heritage" => post_call_str,
            },
          },
        }
        call["record"]["field_value"] << aggregated_field_value
        [call, true]
      end

      def parse_functor_rule(s)
        parts = split(s, ":=")
        return nil unless parts.length == 2
        new_predicate = parse_expression(parts[0])
        definition_expr = parse_expression(parts[1])
        unless definition_expr.key?("call")
          raise ParsingException.new(functor_syntax_error_message, parts[1])
        end
        definition = definition_expr["call"]
        if !new_predicate.key?("literal") || !new_predicate["literal"].key?("the_predicate")
          raise ParsingException.new(functor_syntax_error_message, parts[0])
        end

        applicant = {
          "expression" => {
            "literal" => {
              "the_predicate" => { "predicate_name" => definition["predicate_name"] },
            },
          },
        }
        arguments = { "expression" => { "record" => definition["record"] } }
        {
          "full_text" => s,
          "head" => {
            "predicate_name" => "@Make",
            "record" => {
              "field_value" => [
                { "field" => 0, "value" => { "expression" => new_predicate } },
                { "field" => 1, "value" => applicant },
                { "field" => 2, "value" => arguments },
              ],
            },
          },
        }
      end

      def parse_function_rule(s)
        parts = split_raw(s, "-->")
        return nil unless parts.length == 2
        this_predicate_call = parse_call(parts[0], is_aggregation_allowed: false)
        unless this_predicate_call
          raise ParsingException.new("Left hand side of function definition must be a predicate call.", parts[0])
        end
        annotation = parse_rule(HeritageAwareString.new("@CompileAsUdf(#{this_predicate_call['predicate_name']})"))
        rule = parse_rule(HeritageAwareString.new(parts[0].to_s + " = " + parts[1].to_s))
        [annotation, rule]
      end

      def grab_denotation(head, denotation, with_arguments: false)
        head_couldbe = split(head, denotation)
        if head_couldbe.length > 2
          raise ParsingException.new(
            "Too many >>#{denotation}'s<<, or on it is on incorrect place." \
            "Denotations go as [distrinct] [order_by(...)] [limit(...)].",
            head
          )
        end
        if with_arguments
          if head_couldbe.length == 2
            head_couldbe[1] = strip(head_couldbe[1])
            if head_couldbe[1] && !head_couldbe[1].empty? && head_couldbe[1][0] == "("
              raise ParsingException.new(
                "Can not parse denotations when extracting >>#{denotation}<<. " \
                "Denotations should go as [distinct][order_by][limit].",
                head
              )
            end
            args = parse_record_internals(head_couldbe[1])
            return [head_couldbe[0], true, args]
          end
          return [head, false, nil]
        end

        if head_couldbe.length == 2 && !head_couldbe[1].strip.empty?
          raise ParsingException.new(
            "Too many >>#{denotation}'s<<, or on incorrect place." \
            "Denotations go as [distrinct] [order_by(...)] [limit(...)].",
            head
          )
        end

        [head_couldbe[0], head_couldbe.length == 2]
      end

      def parse_rule(s)
        parts = split(s, ":-")
        if parts.length > 2
          raise ParsingException.new("Too many :- in a rule. Did you forget >>semicolon<<?", s)
        end
        head = parts[0]
        head, couldbe = grab_denotation(head, "couldbe")
        head, cantbe = grab_denotation(head, "cantbe")
        head, shouldbe = grab_denotation(head, "shouldbe")
        head, limit, limit_what = grab_denotation(head, "limit", with_arguments: true)
        head, order_by, order_by_what = grab_denotation(head, "order_by", with_arguments: true)

        head_distinct = split(head, "distinct")
        if head_distinct.length == 1
          parsed_head_call, is_distinct = parse_head_call(head, distinct_from_outside: false)
          raise ParsingException.new("Could not parse head of a rule.", head) unless parsed_head_call
          result = { "head" => parsed_head_call }
          result["distinct_denoted"] = true if is_distinct
        else
          unless head_distinct.length == 2 && (head_distinct[1].nil? || head_distinct[1].empty?)
            raise ParsingException.new("Can not parse rule head. Something is wrong with how >>distinct<< is used.", head)
          end
          parsed_head_call, _is_distinct = parse_head_call(head_distinct[0], distinct_from_outside: true)
          result = { "head" => parsed_head_call, "distinct_denoted" => true }
        end

        result["couldbe_denoted"] = true if couldbe
        result["cantbe_denoted"] = true if cantbe
        result["shouldbe_denoted"] = true if shouldbe
        result["orderby_denoted"] = order_by_what if order_by
        result["limit_denoted"] = limit_what if limit
        if parts.length == 2
          body = parts[1]
          result["body"] = parse_proposition(body)
        end
        result["full_text"] = s
        result
      end

      # Imports and file parsing.
      def split_import(import_str)
        import_path_synonym = split(import_str, " as ")
        if import_path_synonym.length > 2
          raise ParsingException.new("Too many \"as\": #{import_str}", HeritageAwareString.new(import_str))
        end
        import_path = import_path_synonym[0]
        synonym = import_path_synonym.length == 2 ? import_path_synonym[1] : nil
        import_parts = split(import_path, ".")

        import_parts.each do |segment|
          next if segment.match?(/\A[a-zA-Z0-9_]+\z/)

          raise ParsingException.new(
            "Invalid import path segment: #{segment.inspect}. Import segments must match /\\A[a-zA-Z0-9_]+\\z/.",
            segment
          )
        end

        unless import_parts[-1][0].match?(/[A-Z]/)
          raise ParsingException.new(
            "One import per predicate please. Import must end with a PredicateName starting with A-Z. Violator: #{import_str}",
            import_str
          )
        end

        [import_parts[0...-1].join("."), import_parts[-1], synonym]
      end

      def parse_import(file_import_str, parsed_imports, import_chain, import_root)
        file_import_parts = file_import_str.split(".")

        file_import_parts.each do |segment|
          next if segment.match?(/\A[a-zA-Z0-9_]+\z/)

          raise ParsingException.new(
            "Invalid import path segment: #{segment.inspect}. Import segments must match /\\A[a-zA-Z0-9_]+\\z/.",
            HeritageAwareString.new(file_import_str)
          )
        end

        if parsed_imports.key?(file_import_str)
          if parsed_imports[file_import_str].nil?
            raise ParsingException.new(
              "Circular imports are not allowed: %s." % (import_chain + [file_import_str]).join("->"),
              HeritageAwareString.new(file_import_str)
            )
          end
          return nil
        end
        parsed_imports[file_import_str] = nil
        file_path = nil
        if import_root.is_a?(String)
          file_path = File.join(import_root, File.join(file_import_parts) + ".l")
          unless File.exist?(file_path)
            raise ParsingException.new(
              "Imported file not found: #{file_path}.",
              HeritageAwareString.new("import #{file_import_str}.<PREDICATE>")[7..-12]
            )
          end
        else
          unless import_root.is_a?(Array)
            raise "import_root must be of type str or list."
          end
          considered_files = []
          import_root.each do |root|
            file_path = File.join(root, File.join(file_import_parts) + ".l")
            considered_files << file_path
            break if File.exist?(file_path)
          end
          unless File.exist?(file_path)
            raise ParsingException.new(
              "Imported file not found. Considered: \n- #{considered_files.join("\n- ")}.",
              HeritageAwareString.new("import #{file_import_str}.<PREDICATE>")[7..-12]
            )
          end
        end

        file_content = File.read(file_path)
        parsed_file = parse_file(file_content, this_file_name: file_import_str,
                                 parsed_imports: parsed_imports, import_chain: import_chain,
                                 import_root: import_root)
        parsed_imports[file_import_str] = parsed_file
        parsed_file
      end

      def defined_predicates_rules(rules)
        result = {}
        rules.each do |r|
          name = r["head"]["predicate_name"]
          defining_rules = result.fetch(name, [])
          defining_rules << r
          result[name] = defining_rules
        end
        result
      end

      def made_predicates_rules(rules)
        result = {}
        rules.each do |r|
          if r["head"]["predicate_name"] == "@Make"
            name = r["head"]["record"]["field_value"][0]["value"]["expression"]["literal"]["the_predicate"]["predicate_name"]
            result[name] = r
          end
        end
        result
      end

      def defined_predicates(rules)
        defined_predicates_rules(rules).keys.to_set
      end

      def made_predicates(rules)
        made_predicates_rules(rules).keys.to_set
      end

      def rename_predicate(e, old_name, new_name)
        renames_count = 0
        if e.is_a?(Hash)
          if e.key?("predicate_name") && e["predicate_name"] == old_name
            e["predicate_name"] = new_name
            renames_count += 1
          end
          if e.key?("field") && e["field"] == old_name
            e["field"] = new_name
            renames_count += 1
          end
        end
        if e.is_a?(Hash)
          e.each_value do |v|
            if v.is_a?(Hash) || v.is_a?(Array)
              renames_count += rename_predicate(v, old_name, new_name)
            end
          end
        elsif e.is_a?(Array)
          e.each do |v|
            if v.is_a?(Hash) || v.is_a?(Array)
              renames_count += rename_predicate(v, old_name, new_name)
            end
          end
        end
        renames_count
      end

      class MultiBodyAggregation
        SUFFIX = "_MultBodyAggAux"

        def self.strip_heritage(field_values)
          result = LogicaRb::Util.deep_copy(field_values)
          result.each do |fv|
            fv["value"].delete("aggregation")&.delete("expression_heritage")
          end
          result
        end

        def self.rewrite(rules)
          rules = LogicaRb::Util.deep_copy(rules)
          new_rules = []
        defined_rules = LogicaRb::Parser.defined_predicates_rules(rules)
          multi_body_predicates = defined_rules.select { |_n, rs| rs.length > 1 && rs[0].key?("distinct_denoted") }.keys
          aggregation_field_values_per_predicate = {}
          original_full_text_per_predicate = {}
          rules.each do |rule|
            name = rule["head"]["predicate_name"]
            original_full_text_per_predicate[name] = rule["full_text"]
            if multi_body_predicates.include?(name)
              aggregation, new_rule = split_aggregation(rule)
              if aggregation_field_values_per_predicate.key?(name)
                expected = aggregation_field_values_per_predicate[name]
                if strip_heritage(expected) != strip_heritage(aggregation)
                  raise ParsingException.new(
                    "Signature differs for bodies of >>%s<<. Signatures observed: >>%s<<" % [name, [expected, aggregation].to_s],
                    HeritageAwareString.new(rule["full_text"])
                  )
                end
              else
                aggregation_field_values_per_predicate[name] = aggregation
              end
              new_rules << new_rule
            else
              new_rules << rule
            end
          end
          multi_body_predicates.each do |name|
            pass_field_values = aggregation_field_values_per_predicate[name].map do |fv|
              {
                "field" => fv["field"],
                "value" => {
                  "expression" => { "variable" => { "var_name" => fv["field"] } },
                },
              }
            end
            aggregating_rule = {
              "head" => {
                "predicate_name" => name,
                "record" => { "field_value" => aggregation_field_values_per_predicate[name] },
              },
              "body" => {
                "conjunction" => {
                  "conjunct" => [
                    { "predicate" => { "predicate_name" => name + SUFFIX, "record" => { "field_value" => pass_field_values } } },
                  ],
                },
              },
              "full_text" => original_full_text_per_predicate[name],
              "distinct_denoted" => true,
            }
            new_rules << aggregating_rule
          end
          new_rules
        end

        def self.split_aggregation(rule)
          rule = LogicaRb::Util.deep_copy(rule)
          unless rule.key?("distinct_denoted")
            raise ParsingException.new(
              "Inconsistency in >>distinct<< denoting for predicate >>%s<<." % rule["head"]["predicate_name"],
              rule["full_text"]
            )
          end
          rule.delete("distinct_denoted")
          rule["head"]["predicate_name"] = rule["head"]["predicate_name"] + SUFFIX
          transformation_field_values = []
          aggregation_field_values = []
          rule["head"]["record"]["field_value"].each do |field_value|
            if field_value["value"].key?("aggregation")
              aggregation_field_value = {
                "field" => field_value["field"],
                "value" => {
                  "aggregation" => {
                    "operator" => field_value["value"]["aggregation"]["operator"],
                    "argument" => { "variable" => { "var_name" => field_value["field"] } },
                    "expression_heritage" => field_value["value"]["aggregation"]["expression_heritage"],
                  },
                },
              }
              new_field_value = {
                "field" => field_value["field"],
                "value" => { "expression" => field_value["value"]["aggregation"]["argument"] },
              }
              transformation_field_values << new_field_value
              aggregation_field_values << aggregation_field_value
            else
              aggregation_field_value = {
                "field" => field_value["field"],
                "value" => {
                  "expression" => { "variable" => { "var_name" => field_value["field"] } },
                },
              }
              aggregation_field_values << aggregation_field_value
              transformation_field_values << field_value
            end
          end
          rule["head"]["record"]["field_value"] = transformation_field_values
          [aggregation_field_values, rule]
        end
      end

      class DisjunctiveNormalForm
        def self.conjunction_of_dnfs(dnfs)
          return dnfs[0] if dnfs.length == 1
          result = []
          first = dnfs[0]
          others = dnfs[1..]
          first.each do |a|
            conjunction_of_dnfs(others).each do |b|
              result << (a + b)
            end
          end
          result
        end

        def self.conjuncts_to_dnf(conjuncts)
          dnfs = conjuncts.map { |c| proposition_to_dnf(c) }
          conjunction_of_dnfs(dnfs)
        end

        def self.disjuncts_to_dnf(disjuncts)
          dnfs = disjuncts.map { |d| proposition_to_dnf(d) }
          dnfs.flatten(1)
        end

        def self.proposition_to_dnf(proposition)
          return conjuncts_to_dnf(proposition["conjunction"]["conjunct"]) if proposition.key?("conjunction")
          return disjuncts_to_dnf(proposition["disjunction"]["disjunct"]) if proposition.key?("disjunction")
          [[proposition]]
        end

        def self.rule_to_rules(rule)
          return [rule] unless rule.key?("body")
          proposition = rule["body"]
          dnf = proposition_to_dnf(proposition)
          result = []
          dnf.each do |conjuncts|
            new_rule = LogicaRb::Util.deep_copy(rule)
            new_rule["body"] = { "conjunction" => { "conjunct" => LogicaRb::Util.deep_copy(conjuncts) } }
            result << new_rule
          end
          result
        end

        def self.rewrite(rules)
          result = []
          rules.each { |rule| result.concat(rule_to_rules(rule)) }
          result
        end
      end

      class AggergationsAsExpressions
        def self.aggregation_operator(raw_operator)
          return "Agg+" if raw_operator == "+"
          return "Agg++" if raw_operator == "++"
          return "`*`" if raw_operator == "*"
          raw_operator
        end

        def self.convert(a)
          {
            "call" => {
              "predicate_name" => aggregation_operator(a["operator"]),
              "record" => {
                "field_value" => [
                  { "field" => 0, "value" => { "expression" => a["argument"] } },
                ],
              },
            },
            "expression_heritage" => a["expression_heritage"],
          }
        end

        def self.rewrite_internal(s)
          member_index = if s.is_a?(Hash)
                           s.keys.sort_by(&:to_s)
          elsif s.is_a?(Array)
                           (0...s.length).to_a
          else
                           raise "Rewrite should be called on list or dict. Got: #{s}"
          end

          member_index.each do |k|
            if s[k].is_a?(Hash) && s[k].key?("aggregation")
              a = s[k]["aggregation"]
              a["expression"] = convert(a)
              a.delete("operator")
              a.delete("argument")
            end
          end

          member_index.each do |k|
            if s[k].is_a?(Hash) || s[k].is_a?(Array)
              rewrite_internal(s[k])
            end
          end
        end

        def self.rewrite(rules)
          rules = LogicaRb::Util.deep_copy(rules)
          rewrite_internal(rules)
          rules
        end
      end

      def annotations_from_denotations(rule)
        shift_args = lambda do |fvs|
          fvs.each { |fv| fv["field"] += 1 }
        end
        result = []
        [["orderby_denoted", "@OrderBy"], ["limit_denoted", "@Limit"]].each do |denotation, annotation|
          next unless rule.key?(denotation)
          shift_args.call(rule[denotation]["field_value"])
          result << {
            "full_text" => rule["full_text"],
            "head" => {
              "predicate_name" => annotation,
              "record" => {
                "field_value" => [
                  {
                    "field" => 0,
                    "value" => {
                      "expression" => {
                        "literal" => {
                          "the_predicate" => { "predicate_name" => rule["head"]["predicate_name"] },
                        },
                      },
                    },
                  },
                ] + rule[denotation]["field_value"],
              },
            },
          }
        end
        result
      end

      def parse_file(source, this_file_name: nil, parsed_imports: nil, import_chain: nil, import_root: nil)
        enact_incantations(source) if (this_file_name || "main") == "main"
        source = HeritageAwareString.new(remove_comments(HeritageAwareString.new(source)))
        parsed_imports ||= {}
        this_file_name ||= "main"
        import_chain ||= []
        import_chain = import_chain + [this_file_name]
        import_root ||= ""
        str_statements = split(source, ";")
        rules = []
        imported_predicates = []
        predicates_created_by_import = {}
        str_statements.each do |str_statement|
          next if str_statement.nil? || str_statement.empty?
          if str_statement.start_with?("import ")
            import_str = str_statement["import ".length..]
            file_import_str, import_predicate, synonym = split_import(import_str)
            parse_import(file_import_str, parsed_imports, import_chain, import_root)
            imported_predicates << { "file" => file_import_str, "predicate_name" => import_predicate, "synonym" => synonym }
            unless predicates_created_by_import.key?(file_import_str)
              predicates_created_by_import[file_import_str] = (
                defined_predicates(parsed_imports[file_import_str]["rule"]) |
                made_predicates(parsed_imports[file_import_str]["rule"])
              )
            end
            next
          end

          rule = nil
          annotation_and_rule = parse_function_rule(HeritageAwareString.new(str_statement))
          if annotation_and_rule
            annotation, rule = annotation_and_rule
            rules << annotation
          end
          rule ||= parse_functor_rule(HeritageAwareString.new(str_statement))
          unless rule
            rule = parse_rule(HeritageAwareString.new(str_statement))
            rules.concat(annotations_from_denotations(rule)) if rule
          end
          rules << rule if rule
        end

        rules = DisjunctiveNormalForm.rewrite(rules)
        rules = MultiBodyAggregation.rewrite(rules)
        rules = AggergationsAsExpressions.rewrite(rules)

        if this_file_name == "main"
          this_file_prefix = ""
        else
          existing_prefixes = Set.new
          parsed_imports.values.each do |some_parsed_import|
            next unless some_parsed_import
            raise "Empty import prefix: #{some_parsed_import}" if some_parsed_import["predicates_prefix"].nil?
            existing_prefixes.add(some_parsed_import["predicates_prefix"])
          end
          parts = this_file_name.split(".")
          idx = -1
          this_file_prefix = parts[idx].capitalize + "_"
          while existing_prefixes.include?(this_file_prefix)
            idx -= 1
            raise "It looks like some of import paths are equal modulo symbols _ and /. This confuses me: %s" % this_file_prefix if idx <= 0
            this_file_prefix = parts[idx] + this_file_prefix
          end
        end

        if this_file_name != "main"
          (defined_predicates(rules) | made_predicates(rules)).each do |p|
            next if p[0] == "@" || p == "++?"
            rename_predicate(rules, p, this_file_prefix + p)
          end
        end
        imported_predicates.each do |entry|
          imported_predicate_file = entry["file"]
          import_prefix = parsed_imports[imported_predicate_file]["predicates_prefix"]
          raise "Empty import prefix: #{imported_predicate_file}" if import_prefix.nil? || import_prefix.empty?
          imported_predicate_name = entry["predicate_name"]
          predicate_imported_as = entry["synonym"] || imported_predicate_name
          rename_count = rename_predicate(rules, predicate_imported_as, import_prefix + imported_predicate_name)
          unless predicates_created_by_import[imported_predicate_file].include?(import_prefix + imported_predicate_name)
            raise ParsingException.new(
              "Predicate #{imported_predicate_name} from file #{imported_predicate_file} is imported by #{this_file_name}, but is not defined.",
              HeritageAwareString.new("#{imported_predicate_file} -> #{imported_predicate_name}")
            )
          end
          if rename_count.zero?
            raise ParsingException.new(
              "Predicate #{imported_predicate_name} from file #{imported_predicate_file} is imported by #{this_file_name}, but not used.",
              HeritageAwareString.new("#{imported_predicate_file} -> #{predicate_imported_as}")
            )
          end
        end

        if this_file_name == "main"
          defined = defined_predicates(rules)
          parsed_imports.values.each do |imported|
            new_predicates = defined_predicates(imported["rule"])
            if (defined & new_predicates).any? { |p| p[0] != "@" }
              raise ParsingException.new(
                "Predicate from file #{imported['file_name']} is overridden by some importer.",
                HeritageAwareString.new((defined & new_predicates).to_s)
              )
            end
            defined |= new_predicates
            rules.concat(imported["rule"])
          end
        end

        {
          "rule" => rules,
          "imported_predicates" => imported_predicates,
          "predicates_prefix" => this_file_prefix,
          "file_name" => this_file_name,
        }
      end
  end
end
