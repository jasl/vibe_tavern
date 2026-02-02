# frozen_string_literal: true

require "set"
require "json"

require_relative "../common/color"
require_relative "../util"
require_relative "dialects"
require_relative "expr_translate"
require_relative "functors"
require_relative "rule_translate"
require_relative "../parser"
require_relative "../type_inference/research/infer"

module LogicaRb
  module Compiler
    PredicateInfo = Struct.new(:embeddable)
    Ground = Struct.new(:table_name, :overwrite, :copy_to_file)

    def self.format_sql(s)
      "#{s};"
    end

    def self.indent2(s)
      s.split("\n").map { |l| "  #{l}" }.join("\n")
    end

    def self.annotation_error(message, annotation_value)
      raise RuleTranslate::RuleCompileException.new(message, annotation_value["__rule_text"])
    end

    class Logica
      attr_accessor :defines, :export_statements, :defines_and_exports, :table_to_defined_table_map,
                    :table_to_with_sql_map, :table_to_with_dependencies, :with_compilation_done_for_parent,
                    :dependency_edges, :data_dependency_edges, :table_to_export_map, :main_predicate_sql,
                    :preamble, :workflow_predicates_stack, :flags_comment, :compiling_udf, :annotations,
                    :custom_udfs, :custom_udf_definitions, :custom_aggregation_semigroup, :main_predicate,
                    :used_predicates, :dependencies_of, :dialect, :iterations

      def initialize
        @defines = []
        @export_statements = []
        @defines_and_exports = []
        @table_to_defined_table_map = {}
        @table_to_with_sql_map = {}
        @table_to_with_dependencies = Hash.new { |h, k| h[k] = [] }
        @with_compilation_done_for_parent = Hash.new { |h, k| h[k] = Set.new }
        @dependency_edges = []
        @data_dependency_edges = []
        @table_to_export_map = {}
        @main_predicate_sql = nil
        @preamble = ""
        @workflow_predicates_stack = []
        @flags_comment = ""
        @compiling_udf = false
        @annotations = nil
        @custom_udfs = nil
        @custom_udf_definitions = nil
        @custom_aggregation_semigroup = nil
        @main_predicate = nil
        @used_predicates = []
        @dependencies_of = nil
        @dialect = nil
        @iterations = nil
      end

      def add_define(define)
        @defines << define
      end

      def predicate_specific_preamble(predicate_name)
        needed_udfs = @dependencies_of[predicate_name].select { |f| @custom_udf_definitions.key?(f) }
                                            .map { |f| @custom_udf_definitions[f] }
                                            .sort
        needed_semigroups = []
        @dependencies_of[predicate_name].each do |f|
          next unless @custom_aggregation_semigroup&.key?(f)
          semigroup = @custom_udf_definitions[@custom_aggregation_semigroup[f]]
          needed_semigroups << semigroup
          needed_udfs.delete(semigroup)
        end
        (needed_semigroups + needed_udfs).join("\n")
      end

      def needed_udf_definitions
        needed_udfs = @used_predicates.select { |f| @custom_udf_definitions.key?(f) }
                                      .map { |f| @custom_udf_definitions[f] }
                                      .sort
        needed_semigroups = Set.new
        @used_predicates.each do |f|
          next unless @custom_aggregation_semigroup&.key?(f)
          semigroup_definition = @custom_udf_definitions[@custom_aggregation_semigroup[f]]
          needed_semigroups.add(semigroup_definition)
          needed_udfs.delete(semigroup_definition)
        end
        needed_semigroups.to_a + needed_udfs
      end

      def full_preamble
        ([flags_comment, preamble] + defines).join("\n")
      end

      def with(predicate_name)
        return false if compiling_udf
        annotations.with(predicate_name)
      end
    end

    class Annotations
      ANNOTATING_PREDICATES = [
        "@Limit", "@OrderBy", "@Ground", "@Flag", "@DefineFlag",
        "@NoInject", "@Make", "@CompileAsTvf", "@With", "@NoWith",
        "@CompileAsUdf", "@ResetFlagValue", "@Dataset", "@AttachDatabase",
        "@Engine", "@Recursive", "@Iteration", "@BareAggregation",
        "@DifferentiallyPrivate",
        ].freeze

        attr_reader :annotations, :user_flags, :flag_values, :default_engine

        def initialize(rules, user_flags)
          @default_engine = user_flags["logica_default_engine"] || "sqlite"
          @annotations = self.class.extract_annotations(rules, restrict_to: ["@DefineFlag", "@ResetFlagValue"])
          @user_flags = user_flags
          @flag_values = build_flag_values
          @annotations.merge!(self.class.extract_annotations(rules, flag_values: @flag_values))
          check_annotated_objects(rules)
        end

      def preamble
        preamble = ""
        attach = attach_database_statements
        preamble += "#{attach}\n\n" unless attach.empty?
        if engine == "psql"
          preamble += (
            "-- Initializing PostgreSQL environment.\n" \
            "set client_min_messages to warning;\n" \
            "create schema if not exists logica_home;\n" \
            "-- Empty logica type: logicarecord893574736;\n" \
            "DO $$ BEGIN if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord893574736') then create type logicarecord893574736 as (nirvana numeric); end if; END $$;\n\n"
          )
        end
        preamble
      end

      def build_flag_values
        default_values = {}
        @annotations["@DefineFlag"].each { |flag, a| default_values[flag] = a.fetch("1", "${#{flag}}") }
        programmatic_flag_values = {}
        @annotations["@ResetFlagValue"].each { |flag, a| programmatic_flag_values[flag] = a.fetch("1", "${#{flag}}") }
        system_flags = ["logica_default_engine"].to_set
        allowed = default_values.keys.to_set | system_flags
        unless @user_flags.keys.to_set <= allowed
          raise RuleTranslate::RuleCompileException.new(
            "Undefined flags used: #{(@user_flags.keys.to_set - allowed).to_a}",
            (@user_flags.keys.to_set - allowed).to_a.to_s
          )
        end
        flag_values = default_values.merge(programmatic_flag_values)
        flag_values.merge!(@user_flags)
        flag_values
      end

      def no_inject(predicate_name)
        @annotations["@NoInject"].key?(predicate_name)
      end

      def ok_injection(predicate_name)
        return false if order_by(predicate_name) || limit_of(predicate_name) || ground(predicate_name) || no_inject(predicate_name) || force_with(predicate_name)
        true
      end

      def attached_databases
        result = {}
        @annotations["@AttachDatabase"].each do |k, v|
          unless v.key?("1")
            Compiler.annotation_error("@AttachDatabase must have a single argument.", v)
          end
          result[k] = v["1"]
        end
        if engine == "sqlite" && !result.key?("logica_test") && @annotations.key?("@Ground") && @annotations["@Ground"].any?
          result["logica_test"] = ":memory:"
        end
        result
      end

      def attach_database_statements
        lines = []
        attached_databases.each do |k, v|
          lines << "ATTACH DATABASE '#{v}' AS #{k};"
        end
        lines.join("\n")
      end

      def compile_as_udf(predicate_name)
        result = @annotations["@CompileAsUdf"].key?(predicate_name)
        if result && tvf_signature(predicate_name)
          raise RuleTranslate::RuleCompileException.new(
            "A predicate can not be UDF and TVF at the same time #{predicate_name}.",
            "Predicate: #{predicate_name}"
          )
        end
        result
      end

      def tvf_signature(predicate_name)
        return nil unless @annotations["@CompileAsTvf"].key?(predicate_name)
        annotation = @annotations["@CompileAsTvf"][predicate_name]["1"]
        arguments = annotation.map { |x| x["predicate_name"] }
        signature = arguments.map { |a| "#{a} ANY TABLE" }.join(", ")
        "CREATE TEMP TABLE FUNCTION #{predicate_name}(#{signature}) AS "
      end

      def iterations
        result = {}
        @annotations["@Iteration"].each do |iteration_name, args|
          unless args.key?("predicates")
            raise RuleTranslate::RuleCompileException.new("Iteration must specify list of predicates.", args["__rule_text"])
          end
          unless args.key?("repetitions")
            raise RuleTranslate::RuleCompileException.new("Iteration must specify number of repetitions.", args["__rule_text"])
          end
          predicates = args["predicates"].map { |p| p["predicate_name"] }
          result[iteration_name] = { "predicates" => predicates, "repetitions" => args["repetitions"], "stop_signal" => args["stop_signal"] }
        end
        result
      end

      def limit_of(predicate_name)
        return nil unless @annotations["@Limit"].key?(predicate_name)
        annotation = Compiler.field_values_as_list(@annotations["@Limit"][predicate_name])
        unless annotation && annotation.length == 1 && annotation[0].is_a?(Integer)
          raise RuleTranslate::RuleCompileException.new(
            "Bad limit specification for predicate #{predicate_name}.",
            "Predicate: #{predicate_name}"
          )
        end
        annotation[0]
      end

      def order_by(predicate_name)
        return nil unless @annotations["@OrderBy"].key?(predicate_name)
        Compiler.field_values_as_list(@annotations["@OrderBy"][predicate_name])
      end

      def dataset
        default_dataset = engine == "psql" ? "logica_home" : "logica_test"
        if engine == "sqlite" && attached_databases.key?("logica_home")
          default_dataset = "logica_home"
        end
        extract_singleton("@Dataset", default_dataset)
      end

      def engine
        engine = extract_singleton("@Engine", @default_engine)
        return engine if Dialects::DIALECTS.key?(engine)

        raise LogicaRb::UnsupportedEngineError, engine
      end

      def engine_typechecks_by_default(engine_name)
        %w[psql].include?(engine_name)
      end

      def should_typecheck
        eng = engine
        typechecks_by_default = engine_typechecks_by_default(eng)
        return typechecks_by_default unless @annotations["@Engine"]&.any?
        engine_annotation = @annotations["@Engine"].values.first
        return typechecks_by_default unless engine_annotation.key?("type_checking")
        engine_annotation["type_checking"]
      end

      def extract_singleton(annotation_name, default_value)
        return default_value if @annotations[annotation_name].empty?
        results = @annotations[annotation_name].keys
        if results.length > 1
          raise RuleTranslate::RuleCompileException.new(
            "Single #{annotation_name} must be provided. Provided: #{results}",
            @annotations[annotation_name][results[0]]["__rule_text"]
          )
        end
        results[0]
      end

      def ground(predicate_name)
        return nil unless @annotations["@Ground"].key?(predicate_name)
        annotation = @annotations["@Ground"][predicate_name]
        table_name = annotation.fetch("1", "#{dataset}.#{predicate_name}")
        if table_name.is_a?(Hash) && table_name.key?("predicate_name")
          other_ground = ground(table_name["predicate_name"])
          if other_ground
            table_name = other_ground.table_name
          else
            raise RuleTranslate::RuleCompileException.new(
              "Predicate grounded to a non-grounded predicate.",
              annotation["__rule_text"]
            )
          end
        end
        overwrite = annotation.fetch("overwrite", true)
        copy_to_file = annotation["copy_to_file"]
        if copy_to_file && engine != "duckdb"
          raise RuleTranslate::RuleCompileException.new(
            "Copying to file is only supported on DuckDB engine.",
            annotation["__rule_text"]
          )
        end
        Ground.new(table_name, overwrite, copy_to_file)
      end

      def force_with(predicate_name)
        @annotations["@With"].key?(predicate_name)
      end

      def force_no_with(predicate_name)
        @annotations["@NoWith"].key?(predicate_name)
      end

      def with(predicate_name)
        is_with = force_with(predicate_name)
        is_nowith = force_no_with(predicate_name)
        if is_with && is_nowith
          raise RuleTranslate::RuleCompileException.new(
            LogicaRb::Common::Color.format("Predicate is annotated both with @With and @NoWith."),
            "Predicate: #{predicate_name}"
          )
        end
        return true if is_with
        return false if is_nowith || ground(predicate_name)
        true
      end

      def limit_clause(predicate_name)
        limit = limit_of(predicate_name)
        limit ? " LIMIT #{limit}" : ""
      end

      def order_by_clause(predicate_name)
        order_by = order_by(predicate_name)
        return "" unless order_by
        result = []
        (0...(order_by.length - 1)).each do |i|
          if order_by[i + 1] != "DESC"
            result << "#{order_by[i]},"
          else
            result << order_by[i]
          end
        end
        result << order_by[-1]
        " ORDER BY #{result.join(' ')}"
      end

      def check_annotated_objects(rules)
        all_predicates = rules.map { |r| r["head"]["predicate_name"] }.to_set | @annotations["@Ground"].keys.to_set | @annotations["@Make"].keys.to_set
        @annotations.each do |annotation_name, annotated|
          next unless %w[@Limit @OrderBy @NoInject @CompileAsTvf @With @NoWith @CompileAsUdf].include?(annotation_name)
          annotated.each_key do |annotated_predicate|
            next if all_predicates.include?(annotated_predicate)
            rule_text = annotated[annotated_predicate]["__rule_text"]
            Compiler.raise_compiler_error(
              "Annotation #{annotation_name} must be applied to an existing predicate, but it was applied to a non-existing predicate #{annotated_predicate}.",
              rule_text
            )
          end
        end
      end

      def self.extract_annotations(rules, restrict_to: nil, flag_values: nil)
        result = ANNOTATING_PREDICATES.each_with_object({}) { |p, h| h[p] = {} }
        rules.each do |rule|
          rule_predicate = rule["head"]["predicate_name"]
          next if restrict_to && !restrict_to.include?(rule_predicate)
          if rule_predicate.start_with?("@") && !ANNOTATING_PREDICATES.include?(rule_predicate)
            raise RuleTranslate::RuleCompileException.new(
              "Only #{ANNOTATING_PREDICATES[0..-2].join(', ')} and #{ANNOTATING_PREDICATES[-1]} special predicates are allowed.",
              rule["full_text"]
            )
          end
          next unless ANNOTATING_PREDICATES.include?(rule_predicate)

          rule_text = rule["full_text"]
          throw_exception = lambda do |_args = nil|
            if rule_predicate == "@Make"
              raise RuleTranslate::RuleCompileException.new(
                "Incorrect syntax for functor call. Functor call to be made as\n  R := F(A: V, ...)\nor\n  @Make(R, F, {A: V, ...})\nWhere R, F, A's and V's are all predicate names.",
                rule_text
              )
            else
              raise RuleTranslate::RuleCompileException.new("Can not understand annotation.", rule_text)
            end
          end

          thrower = Object.new
          thrower.define_singleton_method(:key?) do |key|
            if rule_predicate == "@Make"
              throw_exception.call
            else
              raise RuleTranslate::RuleCompileException.new(
                "Annotation may not use variables, but this one uses variable #{key}.",
                rule_text
              )
            end
          end
          thrower.define_singleton_method(:[]) { |_key| nil }

          flag_values ||= thrower
          ql = ExprTranslate::QL.new(thrower, throw_exception, throw_exception, flag_values)
          ql.convert_to_json = true

          annotation = rule["head"]["predicate_name"]
          aggregated_fields = rule["head"]["record"]["field_value"].select { |fv| fv["value"].key?("aggregation") }.map { |fv| fv["field"] }
          if aggregated_fields.any?
            raise RuleTranslate::RuleCompileException.new(
              "Annotation may not use aggregation, but field #{aggregated_fields[0]} is aggregated.",
              rule_text
            )
          end
          field_values_json_str = ql.convert_to_sql({ "record" => rule["head"]["record"] })
          begin
            field_values = JSON.parse(field_values_json_str)
          rescue StandardError
            raise RuleTranslate::RuleCompileException.new("Could not understand arguments of annotation.", rule["full_text"])
          end
          subject = if field_values["0"].is_a?(Hash) && field_values["0"].key?("predicate_name")
                      field_values["0"]["predicate_name"]
          else
                      field_values["0"]
          end
          field_values.delete("0")
          if %w[@OrderBy @Limit @NoInject].include?(rule_predicate)
            field_values_list = Compiler.field_values_as_list(field_values)
            if field_values_list.nil?
              raise RuleTranslate::RuleCompileException.new("@OrderBy and @Limit may only have positional arguments.", rule["full_text"])
            end
            if rule_predicate == "@Limit" && field_values_list.length != 1
              raise RuleTranslate::RuleCompileException.new(
                "Annotation @Limit must have exactly two arguments: predicate and limit.",
                rule["full_text"]
              )
            end
          end
          updated_annotation = result[annotation] || {}
          field_values["__rule_text"] = rule["full_text"]
          if updated_annotation.key?(subject)
            raise RuleTranslate::RuleCompileException.new(
              LogicaRb::Common::Color.format(
                "{annotation} annotates {warning}{subject}{end} more than once: {before}, {after}",
                { annotation: annotation, subject: subject, before: updated_annotation[subject]["__rule_text"], after: field_values["__rule_text"] }
              ),
              rule["full_text"]
            )
          end
          updated_annotation[subject] = field_values
          result[annotation] = updated_annotation
        end
        result
      end
    end

    class LogicaProgram
      attr_reader :raw_rules, :preparsed_rules, :rules, :defined_predicates, :dollar_params, :table_aliases,
                  :execution, :user_flags, :annotations, :flag_values, :custom_udfs, :custom_udf_definitions,
                  :custom_aggregation_semigroup, :custom_udf_psql_type, :functors, :typing_preamble,
                  :required_type_definitions, :predicate_signatures, :typing_engine

      def initialize(rules, table_aliases: nil, user_flags: nil, library_profile: :safe)
        @raw_rules = rules
        rules = unfold_recursion(rules)
        @preparsed_rules = rules
        @rules = []
        @defined_predicates = Set.new
        @dollar_params = extract_dollar_params(rules).to_a
        @table_aliases = table_aliases || {}
        @execution = nil
        @user_flags = user_flags || {}
        @library_profile = library_profile
        @annotations = Annotations.new(rules, @user_flags)
        @flag_values = @annotations.flag_values
        @custom_udfs = {}
        @custom_udf_psql_type = {}
        @custom_aggregation_semigroup = {}
        @custom_udf_definitions = {}

        unless @dollar_params.to_set <= @flag_values.keys.to_set
          raise RuleTranslate::RuleCompileException.new(
            "Parameters #{(@dollar_params.to_set - @flag_values.keys.to_set).to_a} are undefined.",
            (@dollar_params.to_set - @flag_values.keys.to_set).to_a.to_s
          )
        end
        @functors = nil

        extended_rules = run_makes(rules)
        library_rules = LogicaRb::Parser.parse_file(Dialects.get(@annotations.engine, library_profile: library_profile).library_program)["rule"]
        extended_rules.concat(library_rules)

        extended_rules.each do |rule|
          predicate_name = rule["head"]["predicate_name"]
          @defined_predicates.add(predicate_name)
          @rules << [predicate_name, rule]
        end
        check_distinct_consistency
        @annotations = Annotations.new(extended_rules, @user_flags)

        @typing_preamble = ""
        @required_type_definitions = {}
        @predicate_signatures = {}
        @typing_engine = nil
        if @annotations.should_typecheck
          @typing_preamble = run_typechecker
        end

        build_udfs
        @execution = nil
      end

      def check_distinct_consistency
        is_distinct = {}
        @rules.each do |p, r|
          distinct_before = is_distinct[p]
          distinct_here = r.key?("distinct_denoted")
          if distinct_before.nil?
            is_distinct[p] = distinct_here
          elsif distinct_before != distinct_here
            raise RuleTranslate::RuleCompileException.new(
              LogicaRb::Common::Color.format(
                "Either all rules of a predicate must be distinct denoted or none. Predicate {warning}{p}{end} violates it.",
                { p: p }
              ),
              r["full_text"]
            )
          end
        end
      end

      def inscribe_orbits(rules, depth_map)
        master = {}
        depth_map.each do |p, args|
          satellite_names = []
          (args["satellites"] || []).each do |s|
            master[s["predicate_name"]] = p
            satellite_names << s["predicate_name"]
          end
          stop_predicate = args["stop"]
          if stop_predicate && !satellite_names.include?(stop_predicate["predicate_name"])
            args["satellites"] ||= []
            args["satellites"] << stop_predicate
          end
        end
        rules.each do |r|
          p = r["head"]["predicate_name"]
          if depth_map.key?(p)
            next unless depth_map[p].key?("satellites")
            r["body"] ||= { "conjunction" => { "conjunct" => [] } }
            r["body"]["conjunction"]["satellites"] = depth_map[p]["satellites"]
          end
          if master.key?(p)
            r["body"] ||= { "conjunction" => { "conjunct" => [] } }
            r["body"]["conjunction"]["satellites"] = [{ "predicate_name" => master[p] }]
          end
        end
      end

      def add_auto_stop(depth_map)
        depth_map.each_key do |k|
          if depth_map.dig(k, "1") == -1 && !depth_map[k].key?("stop")
            depth_map[k]["stop"] = { "predicate_name" => "Stop#{k}" }
          end
        end
      end

      def unfold_recursion(rules)
        annotations = Annotations.new(rules, {})
        depth_map = annotations.annotations.fetch("@Recursive", {})
        add_auto_stop(depth_map)
        inscribe_orbits(rules, depth_map)
        f = Functors::FunctorsEngine.new(rules)
        quacks_like_a_duck = (annotations.engine == "duckdb")
        default_iterative = quacks_like_a_duck
        default_depth = quacks_like_a_duck ? 32 : 8
        f.unfold_recursions(depth_map, default_iterative, default_depth)
      end

      def build_udfs
        initialize_execution("@FunctionsCheck")
        @execution.compiling_udf = true
        remove_udfs = false
        @annotations.annotations["@CompileAsUdf"].each_key do |f|
          @custom_udfs[f] = "DUMMY()" unless remove_udfs
        end
        2.times do
          @annotations.annotations["@CompileAsUdf"].each_key do |f|
            application, sql = function_sql(f, internal_mode: true)
            unless remove_udfs
              @custom_udfs[f] = application
              @custom_udf_definitions[f] = sql
            end
          end
        end
        @annotations.annotations["@BareAggregation"].each do |f, d|
          next if remove_udfs
          unless d.key?("semigroup")
            raise RuleTranslate::RuleCompileException.new(
              LogicaRb::Common::Color.format("Semigroup not specified for aggregation {warning}{f}{end}.", { f: f }),
              @annotations.annotations["@BareAggregation"][f]["__rule_text"]
            )
          end
          semigroup = d["semigroup"]["predicate_name"]
          @custom_udfs[f] = "#{f}({col0})"
          unless @custom_udf_psql_type.key?(semigroup)
            raise RuleTranslate::RuleCompileException.new(
              LogicaRb::Common::Color.format("Semigroup not defined as a UDF for aggregation {warning}{f}{end}.", { f: f }),
              @annotations.annotations["@BareAggregation"][f]["__rule_text"]
            )
          end
          @custom_udf_definitions[f] = (
            "CREATE AGGREGATE #{f} (#{@custom_udf_psql_type[semigroup]}) ( " \
            "  sfunc = #{semigroup}, " \
            "  stype = #{@custom_udf_psql_type[semigroup]});"
          )
          @custom_aggregation_semigroup[f] = semigroup
        end
      end

      def new_names_allocator
        RuleTranslate::NamesAllocator.new(custom_udfs: @custom_udfs)
      end

      def run_typechecker
        rules = @rules.map { |_n, r| r }
        typing_engine = TypeInference::Research::Infer::TypesInferenceEngine.new(rules, @annotations.engine)
        typing_engine.infer_types
        @typing_engine = typing_engine
        type_error_checker = TypeInference::Research::Infer::TypeErrorChecker.new(rules)
        type_error_checker.check_for_error(mode: "raise")
        @predicate_signatures = typing_engine.predicate_signature
        @required_type_definitions.merge!(typing_engine.collector.definitions)
        typing_engine.typing_preamble
      end

      def run_makes(rules)
        return rules unless @annotations.annotations.key?("@Make")
        @functors = Functors::FunctorsEngine.new(rules)
        @functors.make_all(@annotations.annotations["@Make"].to_a)
        @functors.extended_rules
      end

      def self.extract_dollar_params_from_string(s)
        s.scan(/[$][{](.*?)[}]/).flatten.reject { |p| p.start_with?("YYYY") || p == "MM" || p == "DD" }.to_set
      end

      def extract_dollar_params(r)
        if r.is_a?(Hash)
          r.keys.sort_by(&:to_s).map { |k| extract_dollar_params(r[k]) }.reduce(Set.new, &:|)
        elsif r.is_a?(Array)
          r.map { |v| extract_dollar_params(v) }.reduce(Set.new, &:|)
        elsif r.is_a?(String)
          self.class.extract_dollar_params_from_string(r)
        else
          Set.new
        end
      end

      def get_predicate_rules(predicate_name)
        @rules.each do |(n, r)|
          yield r if n == predicate_name
        end
      end

      def check_order_by_clause(name)
        return unless @predicate_signatures.key?(name)
        return unless @annotations.order_by(name)
        order_by_columns = Set.new
        @annotations.order_by(name).each do |c|
          next if %w[desc asc].include?(c)
          col = c.split(" ")[0]
          order_by_columns.add(col)
        end
        actual_columns = Set.new(TypeInference::Research::Infer.argument_names(@predicate_signatures[name]))
        return if actual_columns.include?("*")
        lacking_columns = (order_by_columns - actual_columns).to_a.join(", ")
        if lacking_columns != ""
          raise RuleTranslate::RuleCompileException.new(
            LogicaRb::Common::Color.format(
              "Predicate {warning}{name}{end} is ordered by columns {warning}{columns}{end} which it lacks.",
              { name: name, columns: lacking_columns }
            ),
            @annotations.annotations["@OrderBy"][name]["__rule_text"]
          )
        end
      end

      def predicate_sql(name, allocator = nil, external_vocabulary = nil)
        allocator ||= new_names_allocator
        check_order_by_clause(name)
        rules = []
        get_predicate_rules(name) { |r| rules << r }
        if rules.length == 1
          rule = rules[0]
          result = single_rule_sql(rule, allocator, external_vocabulary, must_not_be_nil: true) +
                   @annotations.order_by_clause(name) + @annotations.limit_clause(name)
          raise "Unexpected nil rule" if result.start_with?("/* nil */")
          result
        elsif rules.length > 1
          rules_sql = []
          rules.each do |rule|
            if rule.key?("distinct_denoted")
              raise RuleTranslate::RuleCompileException.new(
                LogicaRb::Common::Color.format(
                  "For distinct denoted predicates multiple rules are not currently supported. Consider taking {warning}union of bodies manually{end}, if that was what you intended."
                ),
                rule["full_text"]
              )
            end
            single_rule = single_rule_sql(rule, allocator, external_vocabulary)
            rules_sql << "\n#{Compiler.indent2(single_rule)}\n" unless single_rule.start_with?("/* nil */")
          end
          if rules_sql.empty?
            raise RuleTranslate::RuleCompileException.new(
              "All disjuncts are nil for predicate #{name}.",
              rules.last["full_text"]
            )
          end
          rules_sql = rules_sql.map { |r| r.split("\n").map { |l| "  #{l}" }.join("\n") }
          "SELECT * FROM (\n#{rules_sql.join(" UNION ALL\n")}\n) AS UNUSED_TABLE_NAME #{@annotations.order_by_clause(name)} #{@annotations.limit_clause(name)}"
        else
          raise RuleTranslate::RuleCompileException.new(
            LogicaRb::Common::Color.format("No rules are defining {warning}{name}{end}, but compilation was requested.", { name: name }),
            '        ¯\\_(ツ)_/¯'
          )
        end
      end

      def self.turn_positional_into_named(select)
        new_select = {}
        select.each_key do |v|
          if v.is_a?(Integer)
            new_select[select[v]["variable"]["var_name"]] = select[v]
          else
            new_select[v] = select[v]
          end
        end
        new_select
      end

      def function_sql(name, allocator: nil, internal_mode: false)
        allocator ||= new_names_allocator
        rules = []
        get_predicate_rules(name) { |r| rules << r }
        if rules.empty?
          raise RuleTranslate::RuleCompileException.new(
            LogicaRb::Common::Color.format("No rules are defining {warning}{name}{end}, but compilation was requested.", { name: name }),
            '        ¯\\_(ツ)_/¯'
          )
        elsif rules.length > 1
          raise RuleTranslate::RuleCompileException.new(
            LogicaRb::Common::Color.format("Predicate {warning}{name}{end} is defined by more than 1 rule and can not be compiled into a function.", { name: name }),
            rules.map { |r| r["full_text"] }.join("\n\n")
          )
        end
        rule = rules[0]
        s = RuleTranslate.extract_rule_structure(rule, allocator, nil)
        udf_variables = s.select.keys.reject { |v| v == "logica_value" }.map { |v| v.is_a?(String) ? v : "col#{v}" }
        s.select = self.class.turn_positional_into_named(s.select)
        variables = s.select.keys.reject { |v| v == "logica_value" }
        if variables.include?(0)
          raise RuleTranslate::RuleCompileException.new(
            LogicaRb::Common::Color.format("Predicate {warning}{name}{end} must have all aruments named for compilation as a function.", { name: name }),
            rule["full_text"]
          )
        end
        variables.each do |v|
          if !s.select[v].key?("variable") || s.select[v]["variable"]["var_name"] != v
            raise RuleTranslate::RuleCompileException.new(
              LogicaRb::Common::Color.format("Predicate {warning}{name}{end} must not rename arguments for compilation as a function.", { name: name }),
              rule["full_text"]
            )
          end
        end
        vocabulary = variables.each_with_object({}) { |v, h| h[v] = v }
        s.external_vocabulary = vocabulary
        run_injections(s, allocator)
        s.elliminate_internal_variables(assert_full_ellimination: true)
        s.unifications_to_constraints
        sql = s.as_sql(subquery_encoder: make_subquery_translator(allocator))
        if s.constraints.any? || s.unnestings.any? || s.tables.any?
          raise RuleTranslate::RuleCompileException.new(
            LogicaRb::Common::Color.format(
              'Predicate {warning}{name}{end} is not a simple function, but compilation as function was requested. Full SQL:\n{sql}',
              { name: name, sql: sql }
            ),
            rule["full_text"]
          )
        end
        unless s.select.key?("logica_value")
          raise RuleTranslate::RuleCompileException.new(
            LogicaRb::Common::Color.format(
              'Predicate {warning}{name}{end} does not have a value, but compilation as function was requested. Full SQL:\n%s',
              { name: name }
            ),
            rule["full_text"]
          )
        end
        ql = ExprTranslate::QL.new(vocabulary, make_subquery_translator(allocator),
                                   lambda { |message| RuleTranslate::RuleCompileException.new(message, rule["full_text"]) },
                                   @flag_values,
                                   custom_udfs: @custom_udfs,
                                   dialect: @execution.dialect)
        value_sql = ql.convert_to_sql(s.select["logica_value"])
        sql = if @execution.annotations.engine == "psql"
                vartype = lambda do |varname|
                  @typing_engine.collector.psql_type_cache[s.select[varname]["type"]["rendered_type"]]
                end
                @custom_udf_psql_type[name] = vartype.call("logica_value")
                "DROP FUNCTION IF EXISTS #{name} CASCADE; CREATE OR REPLACE FUNCTION #{name}(#{variables.map { |v| "#{v} #{vartype.call(v)}" }.join(', ')}) RETURNS #{vartype.call('logica_value')} AS $$ select (#{value_sql}) $$ language sql"
        else
                "CREATE TEMP FUNCTION #{name}(#{variables.map { |v| "#{v} ANY TYPE" }.join(', ')}) AS (#{value_sql})"
        end
        sql = Compiler.format_sql(sql)
        return ["#{name}(#{udf_variables.map { |v| "{#{v}}" }.join(', ')})", sql] if internal_mode
        sql
      end

      def initialize_execution(main_predicate)
        @execution = Logica.new
        @execution.workflow_predicates_stack << main_predicate
        @execution.preamble = @annotations.preamble
        @execution.annotations = @annotations
        @execution.custom_udfs = @custom_udfs
        @execution.custom_udf_definitions = @custom_udf_definitions
        @execution.custom_aggregation_semigroup = @custom_aggregation_semigroup
        @execution.main_predicate = main_predicate
        @execution.used_predicates = @functors ? @functors.args_of[main_predicate] : []
        @execution.dependencies_of = @functors ? @functors.args_of : {}
        @execution.dialect = Dialects.get(@annotations.engine, library_profile: @library_profile)
        @execution.iterations = @annotations.iterations
      end

      def update_execution_with_typing
        @execution.preamble += "\n#{@typing_preamble}" if @execution.dialect.is_postgresqlish?
      end

      def perform_iteration_closure(allocator)
        participating_predicates = @execution.table_to_defined_table_map.keys
        translator = make_subquery_translator(allocator)
        @execution.iterations.each_value do |iteration|
          iteration_predicates = iteration["predicates"].to_set
          participating_predicates.each do |p|
            next unless iteration_predicates.include?(p)
            iteration_predicates.each do |d|
              translator.translate_table(d, nil, edge_needed: false)
            end
          end
        end
      end

      def formatted_predicate_sql(name, allocator = nil)
        allocator ||= new_names_allocator
        initialize_execution(name)
        if @annotations.compile_as_udf(name)
          @execution.compiling_udf = true
          sql = function_sql(name, allocator: allocator)
        else
          sql = predicate_sql(name, allocator)
        end
        perform_iteration_closure(allocator)
        update_execution_with_typing
        with_signature = generate_with_clauses(name)
        sql = "#{with_signature}\n#{sql}" if with_signature
        @execution.table_to_export_map[name] = sql
        defines_and_exports = @execution.preamble
        udf_definitions = @execution.needed_udf_definitions
        if udf_definitions.any?
          defines_and_exports += "\n\n#{udf_definitions.join("\n\n")}\n\n"
        end
        if @execution.defines_and_exports.any?
          defines_and_exports += "\n\n#{@execution.defines_and_exports.join("\n\n")}\n\n"
        end
        sql = use_flags_as_parameters(sql)
        tvf_signature = @annotations.tvf_signature(name)
        sql = "#{tvf_signature}\n#{sql}" if tvf_signature
        @execution.main_predicate_sql = sql
        formatted_sql = @execution.flags_comment + defines_and_exports + Compiler.format_sql(sql)
        @execution.preamble = use_flags_as_parameters(@execution.preamble)
        @execution.table_to_export_map.transform_values! { |v| use_flags_as_parameters(v) }
        @execution.defines = @execution.defines.map { |d| use_flags_as_parameters(d) }
        @execution.flags_comment = use_flags_as_parameters(@execution.flags_comment)
        @execution.main_predicate_sql = use_flags_as_parameters(@execution.main_predicate_sql)
        use_flags_as_parameters(formatted_sql)
      end

      def use_flags_as_parameters(sql)
        prev_sql = ""
        num_subs = 0
        while sql != prev_sql
          num_subs += 1
          prev_sql = sql
          if num_subs > 100
            raise RuleTranslate::RuleCompileException.new(
              "You seem to have recursive flags. It is disallowed.",
              "Flags:\n" + @flag_values.map { |k, v| "--#{k}=#{v}" }.join("\n")
            )
          end
          @flag_values.each do |flag, value|
            sql = sql.gsub("${#{flag}}", value)
          end
        end
        sql
      end

      def run_injections(s, allocator)
        iterations = 0
        loop do
          iterations += 1
          if iterations > 1000
            raise RuleTranslate::RuleCompileException.new(Compiler.recursion_error, s.full_rule_text)
          end
          new_tables = {}
          s.tables.each do |table_name_rsql, table_predicate_rsql|
            rules = []
            get_predicate_rules(table_predicate_rsql) { |r| rules << r }
            if rules.length == 1 && !rules[0].key?("distinct_denoted") && @annotations.ok_injection(table_predicate_rsql)
              r = rules[0]
              rs = RuleTranslate.extract_rule_structure(r, allocator, nil)
              rs.elliminate_internal_variables(assert_full_ellimination: false, unfold_records: false)
              new_tables.merge!(rs.tables)
              Compiler.inject_structure(s, rs)

              new_vars_map = {}
              new_inv_vars_map = {}
              s.vars_map.each do |(table_name, table_var), clause_var|
                if table_name != table_name_rsql
                  new_vars_map[[table_name, table_var]] = clause_var
                  new_inv_vars_map[clause_var] = [table_name, table_var]
                else
                  if !rs.select.key?(table_var)
                    if rs.select.key?("*")
                      subscript = { "literal" => { "the_symbol" => { "symbol" => table_var } } }
                      s.vars_unification << {
                        "left" => { "variable" => { "var_name" => clause_var } },
                        "right" => { "subscript" => { "subscript" => subscript, "record" => rs.select["*"] } },
                      }
                    elsif table_var == "*"
                      s.vars_unification << { "left" => { "variable" => { "var_name" => clause_var } }, "right" => rs.select_as_record }
                    else
                      extra_hint = table_var == "*" ? " Are you using ..<rest of> for injectible predicate? Please list the fields that you extract explicitly." : ""
                      raise RuleTranslate::RuleCompileException.new(
                        LogicaRb::Common::Color.format(
                          "Predicate {warning}{table_predicate_rsql}{end} does not have an argument {warning}{table_var}{end}, but this rule tries to access it. {extra_hint}",
                          { table_predicate_rsql: table_predicate_rsql, table_var: table_var, extra_hint: extra_hint }
                        ),
                        s.full_rule_text
                      )
                    end
                  else
                    s.vars_unification << { "left" => { "variable" => { "var_name" => clause_var } }, "right" => rs.select[table_var] }
                  end
                end
              end
              s.vars_map = new_vars_map
              s.inv_vars_map = new_inv_vars_map
            else
              new_tables[table_name_rsql] = table_predicate_rsql
            end
          end
          break if s.tables == new_tables
          s.tables = new_tables
        end
      end

      def single_rule_sql(rule, allocator = nil, external_vocabulary = nil, is_combine: false, must_not_be_nil: false)
        allocator ||= new_names_allocator
        r = rule
        r = @execution.dialect.decorate_combine_rule(r, allocator.allocate_var) if is_combine
        s = RuleTranslate.extract_rule_structure(r, allocator, external_vocabulary)
        run_injections(s, allocator)
        s.elliminate_internal_variables(assert_full_ellimination: true)
        s.unifications_to_constraints
        if @annotations.should_typecheck
          type_inference = TypeInference::Research::Infer::TypeInferenceForStructure.new(s, @predicate_signatures, dialect: @annotations.engine)
          type_inference.perform_inference
          error_checker = TypeInference::Research::Infer::TypeErrorChecker.new([type_inference.quazy_rule])
          error_checker.check_for_error("raise")
          @required_type_definitions.merge!(type_inference.collector.definitions)
          @typing_preamble = TypeInference::Research::Infer.build_preamble(@required_type_definitions, dialect: @annotations.engine)
        end
        if s.tables.values.include?("nil")
          if must_not_be_nil
            raise RuleTranslate::RuleCompileException.new(
              "Single rule is nil for predicate #{s.this_predicate_name}. Recursion unfolding failed.",
              rule["full_text"]
            )
          else
            return "/* nil */ SELECT NULL FROM (SELECT 42 AS MONAD) AS NIRVANA WHERE MONAD = 0"
          end
        end
        begin
          sql = s.as_sql(subquery_encoder: make_subquery_translator(allocator), flag_values: @flag_values)
        rescue RuntimeError => e
          if e.message.start_with?("maximum recursion")
            raise RuleTranslate::RuleCompileException.new(Compiler.recursion_error, s.full_rule_text)
          end
          raise
        end
        sql = "/* nil */" + sql if s.tables.values.include?("nil")
        sql
      end

      def generate_with_clauses(predicate_name)
        dependencies = @execution.table_to_with_dependencies[predicate_name]
        return nil if dependencies.empty?
        with_bodies = dependencies.map do |dependency|
          table_name = @execution.table_to_defined_table_map[dependency]
          sql = @execution.table_to_with_sql_map[table_name]
          "#{table_name} AS (#{sql})"
        end
        "WITH #{with_bodies.join(",\n")}"
      end

      def make_subquery_translator(allocator)
        SubqueryTranslator.new(self, allocator, @execution)
      end

      def needs_clingo
        @annotations.annotations.dig("@Engine", "duckdb", "clingo") || false
      end
    end

    class SubqueryTranslator
      attr_reader :execution

      def initialize(program, allocator, execution)
        @program = program
        @allocator = allocator
        @execution = execution
      end

      def translate_table_attached_to_file(table, ground, external_vocabulary, edge_needed: true)
        if edge_needed
          @execution.dependency_edges << [table, @execution.workflow_predicates_stack[-1]]
        end
        return @execution.table_to_defined_table_map[table] if @execution.table_to_defined_table_map.key?(table)
        table_name = ground.table_name
        @execution.table_to_defined_table_map[table] = table_name
        define_statement = "-- Interacting with table #{table_name}"
        @execution.add_define(define_statement)
        export_statement = nil
        if @program.defined_predicates.include?(table)
          @execution.workflow_predicates_stack << table
          dependency_sql = @program.predicate_sql(table, @allocator, external_vocabulary)
          with_signature = @program.generate_with_clauses(table)
          dependency_sql = "#{with_signature}\n#{dependency_sql}" if with_signature
          dependency_sql = @program.use_flags_as_parameters(dependency_sql)
          @execution.workflow_predicates_stack.pop
          maybe_drop_table = "DROP TABLE IF EXISTS #{ground.table_name}#{@execution.dialect.maybe_cascading_deletion_word};\n"
          maybe_copy = ground.copy_to_file ? "COPY #{ground.table_name} TO '#{ground.copy_to_file}';\n" : ""
          export_statement = (
            maybe_drop_table +
            "CREATE TABLE #{ground.table_name} AS #{Compiler.format_sql(dependency_sql)}" +
            maybe_copy
          )
          export_statement = @program.use_flags_as_parameters(export_statement)
          @execution.table_to_export_map[table] = export_statement
          @execution.export_statements << export_statement
        end
        @execution.defines_and_exports << export_statement if export_statement
        @execution.defines_and_exports << define_statement
        table_name
      end

      def translate_withed_table(table)
        parent_table = @execution.workflow_predicates_stack[-1]
        if !@execution.table_to_defined_table_map.key?(table)
          table_name = @allocator.allocate_table(table)
          @execution.table_to_defined_table_map[table] = table_name
          implementation = @program.predicate_sql(table, @allocator)
          @execution.table_to_with_sql_map[table_name] = implementation
        else
          unless @execution.with_compilation_done_for_parent[parent_table].include?(table)
            @program.predicate_sql(table, @allocator)
            @execution.with_compilation_done_for_parent[parent_table].add(table)
          end
        end
        unless @execution.table_to_with_dependencies[parent_table].include?(table)
          @execution.table_to_with_dependencies[parent_table] << table
        end
        @execution.table_to_defined_table_map[table]
      end

      def self.unquote_parenthesised(table)
        if table.length > 4 && table.start_with?("`(") && table.end_with?(")`")
          return table[2..-3]
        end
        table
      end

      def translate_table(table, external_vocabulary, edge_needed: true)
        return @program.table_aliases[table] if @program.table_aliases.key?(table)
        ground = @program.annotations.ground(table)
        return translate_table_attached_to_file(table, ground, external_vocabulary, edge_needed: edge_needed) if ground
        if @program.defined_predicates.include?(table)
          if @program.execution.with(table)
            return translate_withed_table(table)
          end
          return "(#{@program.predicate_sql(table, @allocator, external_vocabulary)})"
        end
        @execution.data_dependency_edges << [table, @execution.workflow_predicates_stack[-1]]
        self.class.unquote_parenthesised(table)
      end

      def translate_rule(rule, external_vocabulary, is_combine: false)
        @program.single_rule_sql(rule, @allocator, external_vocabulary, is_combine: is_combine)
      end
    end

    def self.inject_structure(target, source)
      target.vars_map.merge!(source.vars_map)
      target.inv_vars_map.merge!(source.inv_vars_map)
      target.vars_unification.concat(source.vars_unification)
      target.unnestings.concat(source.unnestings)
      target.constraints.concat(source.constraints)
      target.synonym_log.merge!(source.synonym_log)
    end

    def self.recursion_error
      LogicaRb::Common::Color.format(
        "Recursion in this rule is {warning}too deep{end}. It is running over Python defualt recursion limit. If this is intentional use {warning}sys.setrecursionlimit(10000){end} command in your notebook, or script."
      )
    end

    def self.raise_compiler_error(message, context)
      raise RuleTranslate::RuleCompileException.new(message, context)
    end

    def self.field_values_as_list(field_values)
      field_values = LogicaRb::Util.deep_copy(field_values)
      field_values.delete("__rule_text")
      field_values_list = []
      (0...field_values.length).each do |i|
        key = (i + 1).to_s
        return nil unless field_values.key?(key)
        field_values_list << field_values[key]
      end
      field_values_list
    end
  end
end
