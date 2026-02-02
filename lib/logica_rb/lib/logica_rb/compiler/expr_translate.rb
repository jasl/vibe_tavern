# frozen_string_literal: true

require "json"
require "set"

require_relative "../common/color"
require_relative "../common/data/processed_functions"
require_relative "../util"
require_relative "dialects"

module LogicaRb
  module Compiler
    module ExprTranslate
      class QL
        BUILT_IN_FUNCTIONS = {
          "ToFloat64" => "CAST(%s AS FLOAT64)",
          "ToInt64" => "CAST(%s AS INT64)",
          "ToUInt64" => "CAST(%s AS UINT64)",
          "ToString" => "CAST(%s AS STRING)",
          "1" => "MIN(%s)",
          "Aggr" => "%s",
          "Agg+" => "SUM(%s)",
          "Agg++" => "ARRAY_CONCAT_AGG(%s)",
          "Container" => "%s",
          "Count" => "APPROX_COUNT_DISTINCT(%s)",
          "ExactCount" => "COUNT(DISTINCT %s)",
          "List" => "ARRAY_AGG(%s)",
          "Median" => "APPROX_QUANTILES(%s, 2)[OFFSET(1)]",
          "SomeValue" => "ARRAY_AGG(%s IGNORE NULLS LIMIT 1)[OFFSET(0)]",
          "!" => "NOT %s",
          "-" => "- %s",
          "Concat" => "ARRAY_CONCAT({0}, {1})",
          "Constraint" => "%s",
          "DateAddDay" => "DATE_ADD({0}, INTERVAL {1} DAY)",
          "DateDiffDay" => "DATE_DIFF({0}, {1}, DAY)",
          "Element" => "{0}[OFFSET({1})]",
          "IsNull" => "(%s IS NULL)",
          "Join" => "ARRAY_TO_STRING(%s)",
          "Like" => "({0} LIKE {1})",
          "Range" => "GENERATE_ARRAY(0, %s - 1)",
          "RangeOf" => "GENERATE_ARRAY(0, ARRAY_LENGTH(%s) - 1)",
          "Set" => "ARRAY_AGG(DISTINCT %s)",
          "Size" => "ARRAY_LENGTH(%s)",
          "Sort" => "ARRAY(SELECT x FROM UNNEST(%s) as x ORDER BY x)",
          "TimestampAddDays" => "TIMESTAMP_ADD({0}, INTERVAL {1} DAY)",
          "Unique" => "ARRAY(SELECT DISTINCT x FROM UNNEST(%s) as x ORDER BY x)",
          "ValueOfUnnested" => "%s",
          "MagicalEntangle" => "{0}",
          "FlagValue" => "UNUSED",
          "Cast" => "UNUSED",
          "TryCast" => "UNUSED",
          "SqlExpr" => "UNUSED",
        }.freeze

        BUILT_IN_INFIX_OPERATORS = {
          "==" => "%s = %s",
          "<=" => "%s <= %s",
          "<" => "%s < %s",
          ">=" => "%s >= %s",
          ">" => "%s > %s",
          "/" => "(%s) / (%s)",
          "+" => "(%s) + (%s)",
          "-" => "(%s) - (%s)",
          "*" => "(%s) * (%s)",
          "^" => "POW(%s, %s)",
          "!=" => "%s != %s",
          "++" => "CONCAT(%s, %s)",
          "in" => "%s IN UNNEST(%s)",
          "is" => "%s IS %s",
          "is not" => "%s IS NOT %s",
          "||" => "%s OR %s",
          "&&" => "%s AND %s",
          "%" => "MOD(%s, %s)",
        }.freeze

        ANALYTIC_FUNCTIONS = {
          "CumulativeSum" =>
            "SUM({0}) OVER (PARTITION BY {1} ORDER BY {2} ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)",
          "CumulativeMax" =>
            "MAX({0}) OVER (PARTITION BY {1} ORDER BY {2} ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)",
          "CumulativeMin" =>
            "MIN({0}) OVER (PARTITION BY {1} ORDER BY {2} ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)",
          "WindowSum" =>
            "SUM({0}) OVER (PARTITION BY {1} ORDER BY {2} ROWS BETWEEN {3} PRECEDING AND CURRENT ROW)",
          "WindowMax" =>
            "MAX({0}) OVER (PARTITION BY {1} ORDER BY {2} ROWS BETWEEN {3} PRECEDING AND CURRENT ROW)",
          "WindowMin" =>
            "MIN({0}) OVER (PARTITION BY {1} ORDER BY {2} ROWS BETWEEN {3} PRECEDING AND CURRENT ROW)",
        }.freeze

        @bulk_functions = nil
        @bulk_functions_arity_range = nil

        class << self
          attr_accessor :bulk_functions, :bulk_functions_arity_range
        end

        def initialize(vars_vocabulary, subquery_translator, exception_maker, flag_values, custom_udfs: nil, dialect: nil)
          @dialect = dialect || Dialects::Dialect.new
          @vocabulary = vars_vocabulary
          @subquery_translator = subquery_translator
          @exception_maker = exception_maker
          @debug_undefined_variables = false
          @convert_to_json = false
          @flag_values = flag_values
          @custom_udfs = custom_udfs || {}

          self.class.install_bulk_functions_of_standard_sql
          @bulk_functions = self.class.bulk_functions
          @bulk_function_arity_range = self.class.bulk_functions_arity_range
          @built_in_functions = @bulk_functions.dup
          @built_in_functions.update(BUILT_IN_FUNCTIONS)
          @built_in_functions.update(@dialect.built_in_functions)
          @built_in_infix_operators = BUILT_IN_INFIX_OPERATORS.dup
          @built_in_infix_operators.update(@dialect.infix_operators)
          clean_operators_and_functions
        end

        attr_accessor :convert_to_json

        def str_int_key(k)
          ExprTranslate.str_int_key(k)
        end

        def clean_operators_and_functions
          [@built_in_infix_operators, @built_in_functions].each do |dict|
            dict.keys.each do |k|
              dict.delete(k) if dict[k].nil?
            end
          end
        end

        def self.basis_functions
          install_bulk_functions_of_standard_sql
          (BUILT_IN_FUNCTIONS.keys + BUILT_IN_INFIX_OPERATORS.keys +
           bulk_functions.keys + ANALYTIC_FUNCTIONS.keys).to_set
        end

        def self.install_bulk_functions_of_standard_sql
          return if bulk_functions

          camel_case = lambda do |s|
            s = s.tr(".", "_")
            s.split("_").map { |p| p[0].upcase + p[1..] }.join
          end

          reader = LogicaRb::Common::Data::ProcessedFunctions.get_csv
          header = reader.shift
          bulk_functions = {}
          bulk_ranges = {}
          reader.each do |row|
            row_hash = header.zip(row).to_h
            next if row_hash["function"].start_with?("$")
            function_name = camel_case.call(row_hash["function"])
            bulk_functions[function_name] = "#{row_hash['sql_function']}(%s)"
            bulk_ranges[function_name] = [
              row_hash["min_args"].to_i,
              row_hash["has_repeated_args"] == "1" ? Float::INFINITY : row_hash["max_args"].to_i,
            ]
          end
          self.bulk_functions = bulk_functions
          self.bulk_functions_arity_range = bulk_ranges
        end

        def built_in_function_arity_range(f)
          if BUILT_IN_FUNCTIONS.key?(f)
            return [3, 3] if f == "If"
            arity_2 = %w[RegexpExtract Like ParseTimestamp FormatTimestamp TimestampAddDays Split Element Concat DateAddDay DateDiffDay Join MagicalEntangle]
            return [2, 2] if arity_2.include?(f)
            return [1, 1]
          end
          @bulk_function_arity_range.fetch(f)
        end

        def if_function(args)
          "IF(#{args.join(', ')})"
        end

        def function(f, args)
          args_list = Array.new(args.length)
          args.each { |k, v| args_list[k] = v.to_s }
          if f.include?("%s")
            return format(f, args_list.join(", "))
          end
          f.gsub(/\{(\d+)\}/) { args_list[Regexp.last_match(1).to_i] }
        end

        def infix(op, args)
          if op.include?("%s")
            return format(op, args["left"], args["right"])
          end
          op.gsub(/\{(\w+)\}/) { args.fetch(Regexp.last_match(1)) }
        end

        def subscript(record, subscript, record_is_table)
          subscript = "col#{subscript}" if subscript.is_a?(Integer)
          @dialect.subscript(record, subscript, record_is_table)
        end

        def int_literal(literal)
          literal["number"].to_s
        end

        def str_literal(literal)
          if ["PostgreSQL", "SqLite"].include?(@dialect.name)
            return "'#{literal['the_string'].gsub("'", "''")}'"
          end
          JSON.generate(literal["the_string"], ascii: false)
        end

        def list_literal_internals(literal)
          literal["element"].map { |e| convert_to_sql(e) }.join(", ")
        end

        def list_literal(literal, element_type_name, full_expression)
          if @dialect.is_postgresqlish? && !element_type_name
            raise @exception_maker.call(
              "Type is needed, but not determined for #{full_expression['expression_heritage']}. Please give hints with ~ operator!"
            )
          end
          suffix = @dialect.is_postgresqlish? ? "::#{element_type_name}[]" : ""
          array_phrase = @dialect.array_phrase
          if @convert_to_json
            array_phrase = "[%s]"
            suffix = ""
          end
          format(array_phrase, list_literal_internals(literal)) + suffix
        end

        def bool_literal(literal)
          literal["the_bool"]
        end

        def null_literal(literal)
          literal["the_null"]
        end

        def predicate_literal(literal)
          return "{\"predicate_name\": \"#{literal['predicate_name']}\"}" if @convert_to_json
          @dialect.predicate_literal(literal["predicate_name"])
        end

        def variable_maybe_table_sqlite(variable, expression_type)
          expr = @vocabulary[variable["var_name"]]
          if !expr.include?(".") && !variable.key?("dont_expand")
            unless expression_type.is_a?(Hash)
              raise @exception_maker.call(
                "Could not create record #{expr}. Type inference is required to convert table rows to records in SQLite."
              )
            end
            field_values = expression_type.keys.sort_by { |k| str_int_key(k) }.map do |k|
              {
                "field" => k,
                "value" => {
                  "expression" => {
                    "subscript" => {
                      "record" => { "variable" => { "var_name" => variable["var_name"], "dont_expand" => true } },
                      "subscript" => { "literal" => { "the_symbol" => { "symbol" => k } } },
                    },
                  },
                },
              }
            end
            return convert_to_sql({ "record" => { "field_value" => field_values } })
          end
          expr
        end

        def variable(variable, expression_type)
          if @dialect.name == "SqLite"
            return variable_maybe_table_sqlite(variable, expression_type)
          end
          if @vocabulary.key?(variable["var_name"])
            @vocabulary[variable["var_name"]]
          else
            if @debug_undefined_variables
              "UNDEFINED_#{variable['var_name']}"
            else
              raise "Found no interpretation for #{variable['var_name']} in #{@vocabulary}"
            end
          end
        end

        def convert_record(args)
          result = {}
          args["field_value"].each do |f_v|
            raise "Bad record: #{args}" unless f_v["value"].key?("expression")
            result[f_v["field"]] = convert_to_sql(f_v["value"]["expression"])
          end
          result
        end

        def record_as_json(record)
          json_field_values = record["field_value"].map do |f_v|
            "\"#{f_v['field']}\": #{convert_to_sql(f_v['value']['expression'])}"
          end
          "{#{json_field_values.join(', ')}}"
        end

        def record(record, record_type: nil)
          return record_as_json(record) if @convert_to_json
          if @dialect.name == "SqLite"
            arguments_str = record["field_value"].map do |f_v|
              "'#{f_v['field']}', #{convert_to_sql(f_v['value']['expression'])}"
            end.join(", ")
            return "JSON_OBJECT(#{arguments_str})"
          end
          if @dialect.name == "PostgreSQL"
            raise "Record needs type in PostgreSQL" unless record_type
            args = record["field_value"].sort_by { |fv| str_int_key(fv["field"]) }.map do |f_v|
              convert_to_sql(f_v["value"]["expression"])
            end.join(", ")
            return "ROW(#{args})::#{record_type}"
          end
          arguments_str = record["field_value"].map do |f_v|
            "#{convert_to_sql(f_v['value']['expression'])} AS #{f_v['field']}"
          end.join(", ")
          "STRUCT(#{arguments_str})"
        end

        def generic_sql_expression(record)
          top_record = -> { convert_record(record) }
          if record["field_value"].map { |fv| fv["field"] }.to_set != Set[0, 1]
            raise @exception_maker.call("SqlExpr must have 2 positional arguments, got: #{top_record.call}")
          end
          first_expr = record["field_value"][0]["value"]["expression"]
          unless first_expr.dig("literal", "the_string")
            raise @exception_maker.call("SqlExpr must have first argument be string, got: #{top_record.call[0]}")
          end
          template = first_expr["literal"]["the_string"]["the_string"]
          second_expr = record["field_value"][1]["value"]["expression"]
          unless second_expr.key?("record")
            raise @exception_maker.call("Sectond argument of SqlExpr must be record literal. Got: #{top_record.call[1]}")
          end
          args = convert_record(second_expr["record"])
          template.gsub(/\{(\w+)\}/) { args.fetch(Regexp.last_match(1)) }
        end

        def implication(implication)
          when_then_clauses = implication["if_then"].map do |cond_cons|
            "WHEN #{convert_to_sql(cond_cons['condition'])} THEN #{convert_to_sql(cond_cons['consequence'])}"
          end
          otherwise = convert_to_sql(implication["otherwise"])
          "CASE #{when_then_clauses.join(' ')} ELSE #{otherwise} END"
        end

        def convert_analytic_list_argument(expression)
          if !expression.key?("literal") || !expression["literal"].key?("the_list")
            raise @exception_maker.call(
              "Analytic list argument must resolve to list literal, got: #{convert_to_sql(expression)}"
            )
          end
          list_literal_internals(expression["literal"]["the_list"])
        end

        def convert_analytic(call)
          is_window = call["predicate_name"].start_with?("Window")
          if call["record"]["field_value"].length != 3 + (is_window ? 1 : 0)
            raise @exception_maker.call(
              "Function #{call['predicate_name']} must have #{3 + (is_window ? 1 : 0)} arguments."
            )
          end
          aggregant = convert_to_sql(call["record"]["field_value"][0]["value"]["expression"])
          group_by = convert_analytic_list_argument(call["record"]["field_value"][1]["value"]["expression"])
          order_by = convert_analytic_list_argument(call["record"]["field_value"][2]["value"]["expression"])
          if is_window
            window_size = convert_to_sql(call["record"]["field_value"][3]["value"]["expression"])
            return ANALYTIC_FUNCTIONS[call["predicate_name"]].gsub(/\{(\d+)\}/) do
              idx = Regexp.last_match(1).to_i
              [aggregant, group_by, order_by, window_size][idx]
            end
          end
          ANALYTIC_FUNCTIONS[call["predicate_name"]].gsub(/\{(\d+)\}/) do
            idx = Regexp.last_match(1).to_i
            [aggregant, group_by, order_by][idx]
          end
        end

        def sub_if_struct(implication, subscript)
          get_value = lambda do |field_values, field|
            field_values.each do |field_value|
              return field_value["value"]["expression"] if field_value["field"] == field
            end
            raise @exception_maker.call(
              "Expected field #{subscript} missing in a record inside if statement."
            )
          end
          all_records = implication["if_then"].all? { |if_then| if_then["consequence"].key?("record") }
          return nil unless all_records && implication["otherwise"].key?("record")
          new_if_thens = implication["if_then"].map do |if_then|
            new_if_then = LogicaRb::Util.deep_copy(if_then)
            consequence = get_value.call(if_then["consequence"]["record"]["field_value"], subscript)
            new_if_then["consequence"] = consequence
            new_if_then
          end
          new_otherwise = get_value.call(implication["otherwise"]["record"]["field_value"], subscript)
          new_expr = { "implication" => { "if_then" => new_if_thens, "otherwise" => new_otherwise } }
          convert_to_sql(new_expr)
        end

        def convert_to_sql_for_group_by(expression)
          if expression.dig("literal", "the_string")
            return "(#{convert_to_sql(expression)} || '')"
          end
          if expression.dig("literal", "the_number")
            return "#{convert_to_sql(expression)} + 0"
          end
          convert_to_sql(expression)
        end

        def expression_is_table(expression)
          expression.key?("variable") && expression["variable"].key?("dont_expand") && variable_is_table(expression["variable"]["var_name"])
        end

        def variable_is_table(variable_name)
          !@vocabulary[variable_name].include?(".")
        end

        def convert_to_sql(expression)
          if expression.key?("variable")
            the_type = expression.fetch("type", {}).fetch("the_type", "Any")
            return variable(expression["variable"], the_type)
          end

          if expression.key?("literal")
            literal = expression["literal"]
            return int_literal(literal["the_number"]) if literal.key?("the_number")
            return str_literal(literal["the_string"]) if literal.key?("the_string")
            if literal.key?("the_list")
              element_type = expression.fetch("type", {}).fetch("element_type_name", nil)
              if @dialect.name == "PostgreSQL" && element_type.nil?
                raise @exception_maker.call(
                  LogicaRb::Common::Color.format(
                    "Array needs type in PostgreSQL: {warning}{the_list}{end}.",
                    { the_list: expression["expression_heritage"] }
                  )
                )
              end
              return list_literal(literal["the_list"], element_type, expression)
            end
            return bool_literal(literal["the_bool"]) if literal.key?("the_bool")
            return null_literal(literal["the_null"]) if literal.key?("the_null")
            return predicate_literal(literal["the_predicate"]) if literal.key?("the_predicate")
            raise "Logica bug: unsupported literal parsed: #{literal}"
          end

          if expression.key?("call")
            call = expression["call"]
            arguments = convert_record(call["record"])
            return convert_analytic(call) if ANALYTIC_FUNCTIONS.key?(call["predicate_name"])
            return generic_sql_expression(call["record"]) if call["predicate_name"] == "SqlExpr"
            if %w[Cast TryCast].include?(call["predicate_name"])
              sql_predicate = call["predicate_name"] == "Cast" ? "CAST" : "TRY_CAST"
              if arguments.length == 2 && call["record"]["field_value"][1]["value"]["expression"].key?("record")
                fvs = call["record"]["field_value"]
                type_name = fvs[1]["value"]["expression"]["type"]["type_name"]
                if sql_predicate == "TRY_CAST"
                  return "TRY_CAST(#{convert_to_sql(fvs[0]['value']['expression'])} AS #{type_name})"
                end
                return "(#{convert_to_sql(fvs[0]['value']['expression'])}::#{type_name})"
              end
              unless arguments.length == 2 &&
                     call["record"]["field_value"][1]["value"]["expression"].dig("literal", "the_string")
                raise @exception_maker.call(
                  "Cast must have 2 arguments and the second argument must be a string literal."
                )
              end
              cast_to = call["record"]["field_value"][1]["value"]["expression"]["literal"]["the_string"]["the_string"]
              return "#{sql_predicate}(#{convert_to_sql(call['record']['field_value'][0]['value']['expression'])} AS #{cast_to})"
            end

            if call["predicate_name"] == "FlagValue"
              unless arguments.length == 1 && call["record"]["field_value"][0]["value"]["expression"].dig("literal", "the_string")
                raise @exception_maker.call("FlagValue argument must be a string literal.")
              end
              flag = call["record"]["field_value"][0]["value"]["expression"]["literal"]["the_string"]["the_string"]
              raise @exception_maker.call("Unspecified flag: #{flag}") unless @flag_values.key?(flag)
              return str_literal({ "the_string" => @flag_values[flag] })
            end

            @built_in_functions.each do |ydg_f, sql_f|
              next unless call["predicate_name"] == ydg_f
              raise @exception_maker.call("Function #{ydg_f} is not supported by #{@dialect.name} dialect.") if sql_f.nil?
              next if arguments.length == 2 && ydg_f == "-"
              arity_range = built_in_function_arity_range(ydg_f)
              unless arity_range[0] <= arguments.length && arguments.length <= arity_range[1]
                raise @exception_maker.call(
                  LogicaRb::Common::Color.format(
                    "Built-in function {warning}{ydg_f}{end} takes {a} arguments, but {b} arguments were given.",
                    { ydg_f: ydg_f, a: arity_range, b: arguments.length }
                  )
                )
              end
              return function(sql_f, arguments)
            end

            @custom_udfs.each do |udf, udf_sql|
              if call["predicate_name"] == udf
                arguments = arguments.transform_keys { |k| k.is_a?(String) ? k : "col#{k}" }
                begin
                  return udf_sql.gsub(/\{(\w+)\}/) { arguments.fetch(Regexp.last_match(1)) }
                rescue KeyError
                  raise @exception_maker.call(
                    "Function #{udf} call is inconsistent with its signature #{udf_sql}."
                  )
                end
              end
            end

            @built_in_infix_operators.each do |ydg_op, sql_op|
              next unless call["predicate_name"] == ydg_op
              result = infix(sql_op, arguments)
              return "(#{result})"
            end
          end

          if expression.key?("subscript")
            sub = expression["subscript"]
            subscript = sub["subscript"]["literal"]["the_symbol"]["symbol"]
            if sub["record"].key?("record")
              sub["record"]["record"]["field_value"].each do |f_v|
                return convert_to_sql(f_v["value"]["expression"]) if f_v["field"] == subscript
              end
            end
            if sub["record"].key?("implication")
              simplified = sub_if_struct(sub["record"]["implication"], subscript)
              return simplified if simplified
            end
            record = convert_to_sql(sub["record"])
            return subscript(record, subscript, expression_is_table(sub["record"]))
          end

          if expression.key?("record")
            record_node = expression["record"]
            record_type = expression.fetch("type", {}).fetch("type_name", nil)
            if @dialect.name == "PostgreSQL" && record_type.nil?
              rendered_type = expression.fetch("type", {}).fetch("rendered_type", nil)
              raise @exception_maker.call(
                LogicaRb::Common::Color.format(
                  "Record needs type in PostgreSQL: {warning}{record}{end} was inferred only an incomplete type {warning}{type}{end}.",
                  { record: expression["expression_heritage"], type: rendered_type }
                )
              )
            end
            return record(record_node, record_type: record_type)
          end

          if expression.key?("combine")
            combined_value = "(#{@subquery_translator.translate_rule(expression['combine'], @vocabulary, is_combine: true)})"
            if @dialect.name == "PostgreSQL"
              unless expression.fetch("type", {}).key?("combine_psql_type")
                rendered_type = expression.fetch("type", {}).fetch("rendered_type", nil)
                raise @exception_maker.call(
                  LogicaRb::Common::Color.format(
                    "Aggregating expression needs type in PostgreSQL: {warning}{expr}{end} was inferred only an incomplete type {warning}{type}{end}.",
                    { expr: expression["expression_heritage"], type: rendered_type }
                  )
                )
              end
              return "CAST(#{combined_value} AS #{expression['type']['combine_psql_type']})"
            end
            return combined_value
          end

          if expression.key?("implication")
            return implication(expression["implication"])
          end

          if expression.key?("call") && expression["call"].key?("predicate_name")
            raise @exception_maker.call(
              LogicaRb::Common::Color.format(
                "Unsupported supposedly built-in function: {warning}{predicate}{end}.",
                { predicate: expression["call"]["predicate_name"] }
              )
            )
          end
          raise "Logica bug: expression #{expression} failed to compile for unknown reason."
        end
      end

      def self.str_int_key(k)
        return k if k.is_a?(String)
        return format("%03d", k) if k.is_a?(Integer)
        raise "x:#{k}"
      end

      def self.StrIntKey(k)
        str_int_key(k)
      end

      def self.convert_record_key(k)
        str_int_key(k)
      end

      def self.str_int_key_pair(k, _v)
        str_int_key(k)
      end

      def self.StrIntKeyPair(k, v)
        str_int_key_pair(k, v)
      end
    end
  end
end
