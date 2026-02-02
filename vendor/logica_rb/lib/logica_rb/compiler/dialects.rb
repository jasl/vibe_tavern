# frozen_string_literal: true

require_relative "../util"
require_relative "dialect_libraries/sqlite_library"
require_relative "dialect_libraries/psql_library"

module LogicaRb
  module Compiler
    module Dialects
      def self.get(engine, library_profile: :safe)
        klass = DIALECTS.fetch(engine) do
          raise ArgumentError, "Unknown dialect: #{engine}"
        end
        klass.new(library_profile: library_profile)
      end

      class Dialect
        def initialize(library_profile: :safe)
          @library_profile = normalize_library_profile(library_profile)
        end

        attr_reader :library_profile

        def name
          "Generic"
        end

        def built_in_functions
          {}
        end

        def infix_operators
          {}
        end

        def subscript(record, subscript, _record_is_table)
          "#{record}.#{subscript}"
        end

        def unnest_phrase
          "UNNEST(%s) as %s"
        end

        def array_phrase
          "ARRAY[%s]"
        end

        def group_by_spec_by
          "expr"
        end

        def maybe_cascading_deletion_word
          ""
        end

        def predicate_literal(predicate_name)
          "'predicate_name:#{predicate_name}'"
        end

        def is_postgresqlish?
          false
        end

        private

        def normalize_library_profile(value)
          profile = (value || :safe).to_sym
          return profile if %i[safe full].include?(profile)

          raise ArgumentError, "Unknown library_profile: #{value.inspect} (expected :safe or :full)"
        end
      end

      class SqLiteDialect < Dialect
        def name
          "SqLite"
        end

        def built_in_functions
          {
            "Set" => "DistinctListAgg({0})",
            "Element" => "JSON_EXTRACT({0}, '$[' || {1} || ']')",
            "Range" => "(select json_group_array(n) from (with recursive t as" \
                       "(select 0 as n union all " \
                       "select n + 1 as n from t where n + 1 < {0}) " \
                       "select n from t) where n < {0})",
            "ValueOfUnnested" => "{0}.value",
            "List" => "JSON_GROUP_ARRAY({0})",
            "Size" => "JSON_ARRAY_LENGTH({0})",
            "Join" => "JOIN_STRINGS({0}, {1})",
            "Count" => "COUNT(DISTINCT {0})",
            "StringAgg" => "GROUP_CONCAT(%s)",
            "Sort" => "SortList({0})",
            "MagicalEntangle" => "MagicalEntangle({0}, {1})",
            "Format" => "Printf(%s)",
            "Least" => "MIN(%s)",
            "Greatest" => "MAX(%s)",
            "ToString" => "CAST(%s AS TEXT)",
            "DateAddDay" => "DATE({0}, {1} || ' days')",
            "DateDiffDay" => "CAST(JULIANDAY({0}) - JULIANDAY({1}) AS INT64)",
          }
        end

        def decorate_combine_rule(rule, var)
          Dialects.decorate_combine_rule(rule, var)
        end

        def infix_operators
          {
            "++" => "(%s) || (%s)",
            "%" => "(%s) %% (%s)",
            "in" => "IN_LIST(%s, %s)",
          }
        end

        def subscript(record, subscript, record_is_table)
          if record_is_table
            "#{record}.#{subscript}"
          else
            "JSON_EXTRACT(#{record}, \"$.#{subscript}\")"
          end
        end

        def library_program
          case library_profile
          when :safe
            DialectLibraries::SqliteLibrary::SAFE_LIBRARY
          when :full
            DialectLibraries::SqliteLibrary::FULL_LIBRARY
          else
            raise ArgumentError, "Unknown library_profile: #{library_profile.inspect}"
          end
        end

        def unnest_phrase
          "JSON_EACH(%s) as %s"
        end

        def array_phrase
          "JSON_ARRAY(%s)"
        end

        def group_by_spec_by
          "expr"
        end
      end

      class PostgreSQL < Dialect
        def name
          "PostgreSQL"
        end

        def built_in_functions
          {
            "Range" => "(SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, {0} - 1) as x)",
            "RangeOf" => "(SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, ARRAY_LENGTH({0}, 1) - 1) as x)",
            "ToString" => "CAST(%s AS TEXT)",
            "ToInt64" => "CAST(%s AS BIGINT)",
            "ToFloat64" => "CAST(%s AS double precision)",
            "Element" => "({0})[{1} + 1]",
            "Size" => "COALESCE(ARRAY_LENGTH({0}, 1), 0)",
            "Count" => "COUNT(DISTINCT {0})",
            "MagicalEntangle" => "(CASE WHEN {1} = 0 THEN {0} ELSE NULL END)",
            "ArrayConcat" => "{0} || {1}",
            "Split" => "STRING_TO_ARRAY({0}, {1})",
            "AnyValue" => "(ARRAY_AGG(%s))[1]",
            "Log" => "LN(%s)",
          }
        end

        def infix_operators
          {
            "++" => "%s || %s",
            "in" => "%s = ANY(%s)",
          }
        end

        def subscript(record, subscript, _record_is_table)
          "(#{record}).#{subscript}"
        end

        def library_program
          case library_profile
          when :safe
            DialectLibraries::PsqlLibrary::SAFE_LIBRARY
          when :full
            DialectLibraries::PsqlLibrary::FULL_LIBRARY
          else
            raise ArgumentError, "Unknown library_profile: #{library_profile.inspect}"
          end
        end

        def unnest_phrase
          "UNNEST(%s) as %s"
        end

        def array_phrase
          "ARRAY[%s]"
        end

        def group_by_spec_by
          "expr"
        end

        def decorate_combine_rule(rule, var)
          Dialects.decorate_combine_rule(rule, var)
        end

        def maybe_cascading_deletion_word
          " CASCADE"
        end

        def is_postgresqlish?
          true
        end
      end

      def self.decorate_combine_rule(rule, var)
        rule = LogicaRb::Util.deep_copy(rule)
        rule["head"]["record"]["field_value"][0]["value"]["aggregation"]["expression"]["call"]["record"]["field_value"][0]["value"] = {
          "expression" => {
            "call" => {
              "predicate_name" => "MagicalEntangle",
              "record" => {
                "field_value" => [
                  {
                    "field" => 0,
                    "value" => rule["head"]["record"]["field_value"][0]["value"]["aggregation"]["expression"]["call"]["record"]["field_value"][0]["value"],
                  },
                  {
                    "field" => 1,
                    "value" => {
                      "expression" => { "variable" => { "var_name" => var } },
                    },
                  },
                ],
              },
            },
          },
        }

        rule["body"] ||= { "conjunction" => { "conjunct" => [] } }
        rule["body"]["conjunction"]["conjunct"] << {
          "inclusion" => {
            "list" => {
              "literal" => {
                "the_list" => {
                  "element" => [
                    { "literal" => { "the_number" => { "number" => "0" } } },
                  ],
                },
              },
            },
            "element" => { "variable" => { "var_name" => var } },
          },
        }
        rule
      end

      DIALECTS = {
        "sqlite" => SqLiteDialect,
        "psql" => PostgreSQL,
      }.freeze
    end
  end
end
