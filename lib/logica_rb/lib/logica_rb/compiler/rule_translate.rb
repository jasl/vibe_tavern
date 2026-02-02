# frozen_string_literal: true

require "set"

require_relative "../common/color"
require_relative "../util"
require_relative "expr_translate"

module LogicaRb
  module Compiler
    module RuleTranslate
      extend self

      LogicalVariable = Struct.new(:variable_name, :predicate_name, :is_user_variable)

      def indent2(s)
        s.split("\n").map { |l| "  #{l}" }.join("\n")
      end

      class RuleCompileException < StandardError
        attr_reader :rule_str

        def initialize(message, rule_str)
          super(message)
          @rule_str = rule_str
        end

        def show_message(stream = $stderr)
          stream.puts(LogicaRb::Common::Color.format("{underline}Compiling{end}:"))
          stream.puts(@rule_str)
          stream.puts(LogicaRb::Common::Color.format("\n[ {error}Error{end} ] ") + message)
        end
      end

      def logica_field_to_sql_field(logica_field)
        return "col#{logica_field}" if logica_field.is_a?(Integer)
        logica_field
      end

      def head_to_select(head)
        select = {}
        aggregated_vars = []
        head["record"]["field_value"].each do |field_value|
          k = field_value["field"]
          v = field_value["value"]
          if v.key?("aggregation")
            select[k] = LogicaRb::Util.deep_copy(v["aggregation"]["expression"])
            aggregated_vars << k
          else
            raise "Bad select value: #{v}" unless v.key?("expression")
            select[k] = v["expression"]
          end
        end
        if select.empty?
          select["atom"] = { "literal" => { "the_string" => { "the_string" => "yes" } } }
        end
        [select, aggregated_vars]
      end

      def all_mentioned_variables(x, dive_in_combines: false, this_is_select: false)
        r = Set.new
        if x.is_a?(Hash) && x.key?("variable") && !this_is_select
          r.add(x["variable"]["var_name"])
        end
        if x.is_a?(Array)
          x.each { |v| r.merge(all_mentioned_variables(v, dive_in_combines: dive_in_combines)) }
        end
        if x.is_a?(Hash)
          x.each do |k, v|
            next if k == "combine" && !dive_in_combines
            if v.is_a?(Hash) || v.is_a?(Array)
              r.merge(all_mentioned_variables(v, dive_in_combines: dive_in_combines))
            end
          end
        end
        r
      end

      def replace_variable(old_var, new_expr, s)
        member_index = if s.is_a?(Hash)
                         s.keys.sort_by(&:to_s)
        elsif s.is_a?(Array)
                         (0...s.length).to_a
        else
                         raise "Replace should be called on list or dict. Got: #{s}"
        end
        member_index.each do |k|
          if s[k].is_a?(Hash) && s[k].key?("variable") && s[k]["variable"]["var_name"] == old_var
            s[k] = new_expr
          end
        end
        if s.is_a?(Hash)
          s.each_value do |v|
            replace_variable(old_var, new_expr, v) if v.is_a?(Hash) || v.is_a?(Array)
          end
        elsif s.is_a?(Array)
          s.each do |v|
            replace_variable(old_var, new_expr, v) if v.is_a?(Hash) || v.is_a?(Array)
          end
        end
      end

      class NamesAllocator
        def initialize(custom_udfs: nil)
          @aux_var_num = 0
          @table_num = 0
          @allocated_tables = Set.new
          @custom_udfs = custom_udfs || {}
        end

        def allocate_var(_hint = nil)
          v = "x_#{@aux_var_num}"
          @aux_var_num += 1
          v
        end

        def allocate_table(hint_for_user = nil)
          allowed_chars = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a + ["_", ".", "/"]
          suffix = ""
          if hint_for_user && hint_for_user.length < 100
            suffix = hint_for_user.chars.select { |c| allowed_chars.include?(c) }
                                   .map { |c| [".", "/"].include?(c) ? "_" : c }.join
          end
          if !suffix.empty? && !@allocated_tables.include?(suffix) && !suffix[0].match?(/\d/)
            t = suffix
          else
            suffix = "_#{suffix}" unless suffix.empty?
            t = "t_#{@table_num}#{suffix}"
            @table_num += 1
          end
          @allocated_tables.add(t)
          t
        end

        def function_exists?(function_name)
          ExprTranslate::QL.basis_functions.include?(function_name) || @custom_udfs.key?(function_name)
        end
      end

      class ExceptExpression
        def self.build(table_name, except_fields)
          "(SELECT AS STRUCT #{table_name}.* EXCEPT (#{except_fields.join(',')}))"
        end

        def self.recognize(field_name)
          field_name.start_with?("(SELECT AS STRUCT")
        end
      end

      class RuleStructure
        attr_accessor :this_predicate_name, :tables, :vars_map, :vars_heritage_map, :inv_vars_map,
                      :vars_unification, :constraints, :select, :unnestings, :distinct_vars,
                      :allocator, :external_vocabulary, :synonym_log, :full_rule_text, :distinct_denoted

        def initialize(names_allocator = nil, external_vocabulary = nil, custom_udfs: nil)
          @this_predicate_name = ""
          @tables = {}
          @vars_map = {}
          @vars_heritage_map = {}
          @inv_vars_map = {}
          @vars_unification = []
          @constraints = []
          @select = {}
          @unnestings = []
          @distinct_vars = []
          @allocator = names_allocator || NamesAllocator.new(custom_udfs: custom_udfs)
          @external_vocabulary = external_vocabulary
          @synonym_log = {}
          @full_rule_text = nil
          @distinct_denoted = nil
        end

        def select_as_record
          ordered = @select.sort_by do |k, _v|
            if k.is_a?(String)
              k
            elsif k.is_a?(Integer)
              format("%03d", k)
            else
              raise "x:#{k}"
            end
          end
          {
            "record" => {
              "field_value" => ordered.map do |k, v|
                { "field" => k, "value" => { "expression" => v } }
              end,
            },
          }
        end

        def own_vars_vocabulary
          table_and_field_to_sql = lambda do |table, field|
            return field if ExceptExpression.recognize(field)
            return "#{table}.#{field}" if table && field != "*"
            return field unless table
            table
          end
          @inv_vars_map.each_with_object({}) do |(var_name, (table, field)), h|
            h[var_name] = table_and_field_to_sql.call(table, RuleTranslate.logica_field_to_sql_field(field))
          end
        end

        def vars_vocabulary
          r = own_vars_vocabulary
          r.merge!(@external_vocabulary) if @external_vocabulary
          r
        end

        def extracted_variables
          vars_vocabulary.keys.to_set
        end

        def internal_variables
          all_variables - extracted_variables
        end

        def all_variables
          r = Set.new
          r.merge(RuleTranslate.all_mentioned_variables(@select, this_is_select: true))
          r.merge(RuleTranslate.all_mentioned_variables(@vars_unification))
          r.merge(RuleTranslate.all_mentioned_variables(@constraints))
          r.merge(RuleTranslate.all_mentioned_variables(@unnestings))
          r
        end

        def sort_unnestings
          unnesting_of = @unnestings.to_h { |u| [u[0]["variable"]["var_name"], u] }
          unnesting_variables = unnesting_of.keys.to_set
          depends_on = @unnestings.each_with_object({}) do |u, h|
            h[u[0]["variable"]["var_name"]] =
              RuleTranslate.all_mentioned_variables(u[1], dive_in_combines: true) & unnesting_variables
          end

          unnested = Set.new
          ordered = []
          while unnesting_of.any?
            progress = false
            unnesting_of.sort.each do |v, _u|
              next unless depends_on[v] <= unnested
              ordered << unnesting_of[v]
              unnesting_of.delete(v)
              unnested.add(v)
              progress = true
              break
            end
            unless progress
              raise RuleCompileException.new(
                LogicaRb::Common::Color.format(
                  "There seem to be a circular dependency of {warning}In{end} calls. This error might also come from injected sub-rules."
                ),
                @full_rule_text
              )
            end
          end
          @unnestings = ordered
        end

        def replace_variable_everywhere(u_left, u_right)
          if u_right.is_a?(Hash) && u_right.key?("variable")
            l = @synonym_log.fetch(u_right["variable"]["var_name"], [])
            l << LogicalVariable.new(u_left, @this_predicate_name, !u_left.to_s.start_with?("x_"))
            l.concat(@synonym_log.fetch(u_left, []))
            @synonym_log[u_right["variable"]["var_name"]] = l
          end
          RuleTranslate.replace_variable(u_left, u_right, @unnestings)
          RuleTranslate.replace_variable(u_left, u_right, @select)
          RuleTranslate.replace_variable(u_left, u_right, @vars_unification)
          RuleTranslate.replace_variable(u_left, u_right, @constraints)
        end

        def elliminate_internal_variables(assert_full_ellimination: false, unfold_records: true)
          variables = internal_variables
          loop do
            done = true
            @vars_unification = @vars_unification.reject { |u| u["left"] == u["right"] }
            @vars_unification.each do |u|
              [["left", "right"], ["right", "left"]].each do |k, r|
                next if u[k] == u[r]
                ur_variables = RuleTranslate.all_mentioned_variables(u[r])
                ur_variables_incl_combines = RuleTranslate.all_mentioned_variables(u[r], dive_in_combines: true)
                if u[k].is_a?(Hash) && u[k].key?("variable") &&
                   variables.include?(u[k]["variable"]["var_name"]) &&
                   !ur_variables_incl_combines.include?(u[k]["variable"]["var_name"]) &&
                   (ur_variables <= extracted_variables || !u[k]["variable"]["var_name"].to_s.start_with?("x_"))
                  u_left = u[k]["variable"]["var_name"]
                  u_right = u[r]
                  replace_variable_everywhere(u_left, u_right)
                  done = false
                end
              end

              if unfold_records
                [["left", "right"], ["right", "left"]].each do |k, r|
                  next if u[k] == u[r]
                  ur_variables = RuleTranslate.all_mentioned_variables(u[r])
                  ur_variables_incl_combines = RuleTranslate.all_mentioned_variables(u[r], dive_in_combines: true)
                  if u[k].is_a?(Hash) && u[k].key?("record") && ur_variables <= extracted_variables
                    assign_to_record = lambda do |target, source|
                      target["record"]["field_value"].each do |fv|
                        make_new_source = lambda do
                          {
                            "subscript" => {
                              "record" => source,
                              "subscript" => { "literal" => { "the_symbol" => { "symbol" => fv["field"] } } },
                            },
                          }
                        end
                        if fv["value"]["expression"].is_a?(Hash) &&
                           fv["value"]["expression"].key?("variable") &&
                           variables.include?(fv["value"]["expression"]["variable"]["var_name"]) &&
                           !ur_variables_incl_combines.include?(fv["value"]["expression"]["variable"]["var_name"])
                          u_left = fv["value"]["expression"]["variable"]["var_name"]
                          u_right = make_new_source.call
                          replace_variable_everywhere(u_left, u_right)
                          done = false
                        end
                        if fv["value"]["expression"].is_a?(Hash) && fv["value"]["expression"].key?("record")
                          new_target = fv["value"]["expression"]
                          new_source = make_new_source.call
                          assign_to_record.call(new_target, new_source)
                        end
                      end
                    end
                    assign_to_record.call(u[k], u[r])
                  end
                end
              end
            end

            if done
              variables = internal_variables
              if assert_full_ellimination
                if variables.any?
                  violators = []
                  variables.each do |v|
                    violators.concat(@synonym_log.fetch(v, []).map(&:variable_name).select { |vv| !vv.nil? })
                    violators << v
                  end
                  violators = violators.reject { |v| v.to_s.start_with?("x_") }
                  if violators.any?
                    violators = violators.map { |v| v.to_s.split(" # disambiguated")[0] }.to_set
                    raise RuleCompileException.new(
                      LogicaRb::Common::Color.format(
                        "Found no way to assign variables: {warning}{violators}{end}.",
                        { violators: violators.to_a.sort.join(", ") }
                      ),
                      @full_rule_text
                    )
                  else
                    user_variables = variables.flat_map { |v| @synonym_log.fetch(v, []) }.select(&:is_user_variable)
                    this_predicate = LogicaRb::Common::Color.format("{warning}{p}{end}", { p: @this_predicate_name })
                    unassigned_vars = user_variables.map do |uv|
                      LogicaRb::Common::Color.format(
                        "{warning}{var}{end} in rule for {warning}{p}{end}",
                        { var: uv.variable_name, p: uv.predicate_name }
                      )
                    end.join(", ")
                    raise RuleCompileException.new(
                      "While compiling predicate #{this_predicate} there was found no way to assign variables: #{unassigned_vars}.",
                      @full_rule_text
                    )
                  end
                end
              else
                unassigned_variables = variables.reject { |v| v.to_s.start_with?("x_") }
                unassigned_variables = unassigned_variables.map { |v| v.to_s.split(" # disambiguated")[0] }.to_set
                if unassigned_variables.any?
                  raise RuleCompileException.new(
                    LogicaRb::Common::Color.format(
                      "Found no way to assign variables: {warning}{violators}{end}. This error might also come from injected sub-rules.",
                      { violators: unassigned_variables.to_a.sort.join(", ") }
                    ),
                    @full_rule_text
                  )
                end
              end
              break
            end
          end
        end

        def unifications_to_constraints
          @vars_unification.each do |u|
            next if u["left"] == u["right"]
            @constraints << {
              "call" => {
                "predicate_name" => "==",
                "record" => {
                  "field_value" => [
                    { "field" => "left", "value" => { "expression" => u["left"] } },
                    { "field" => "right", "value" => { "expression" => u["right"] } },
                  ],
                },
              },
            }
          end
        end

        def as_sql(subquery_encoder: nil, flag_values: nil)
          ql = ExprTranslate::QL.new(
            vars_vocabulary,
            subquery_encoder,
            lambda { |message| RuleCompileException.new(message, @full_rule_text) },
            flag_values,
            custom_udfs: subquery_encoder.execution.custom_udfs,
            dialect: subquery_encoder.execution.dialect
          )
          r = "SELECT\n"
          if subquery_encoder.execution.annotations.annotations["@DifferentiallyPrivate"].key?(@this_predicate_name)
            r += "WITH DIFFERENTIAL_PRIVACY\n"
          end
          if @select.empty?
            raise RuleCompileException.new(
              LogicaRb::Common::Color.format(
                "Tables with {warning}no columns{end} are not allowed in StandardSQL, so they are not allowed in Logica."
              ),
              @full_rule_text
            )
          end
          fields = []
          @select.each do |k, v|
            if k == "*"
              if v.key?("variable")
                v["variable"]["dont_expand"] = true
              end
              fields << subquery_encoder.execution.dialect.subscript(ql.convert_to_sql(v), "*", true)
            else
                fields << "#{ql.convert_to_sql(v)} AS #{RuleTranslate.logica_field_to_sql_field(k)}"
            end
          end
          r += fields.map { |f| "  #{f}" }.join(",\n")
          if @tables.any? || @unnestings.any? || @constraints.any? || @distinct_denoted
            r += "\nFROM\n"
            tables = []
            @tables.each do |k, v|
              sql = nil
              if subquery_encoder
                sql = subquery_encoder.translate_table(v, @external_vocabulary)
                unless sql
                  raise RuleCompileException.new(
                    LogicaRb::Common::Color.format(
                      "Rule uses table {warning}{table}{end}, which is not defined. External tables can not be used in {warning}'testrun'{end} mode. This error may come from injected sub-rules.",
                      { table: v }
                    ),
                    @full_rule_text
                  )
                end
              end
              tables << (sql != k ? "#{sql} AS #{k}" : sql)
            end
            sort_unnestings
            @unnestings.each do |element, the_list|
              element["variable"]["dont_expand"] = true if element.key?("variable")
              tables << format(
                subquery_encoder.execution.dialect.unnest_phrase,
                ql.convert_to_sql(the_list),
                ql.convert_to_sql(element)
              )
            end
            tables << "(SELECT 'singleton' as s) as unused_singleton" if tables.empty?
            from_str = tables.join(", ")
            from_str = from_str.split("\n").map { |l| "  #{l}" }.join("\n")
            r += from_str
            if @constraints.any?
              constraints = []
              ephemeral_predicates = ["~"]
              @constraints.each do |c|
                next if ephemeral_predicates.include?(c["call"]["predicate_name"])
                constraints << ql.convert_to_sql(c)
              end
              if constraints.any?
                r += "\nWHERE\n"
                r += constraints.map { |c| RuleTranslate.indent2(c) }.join(" AND\n")
              end
            end
            if @distinct_vars.any?
              ordered_distinct_vars = @select.keys.select { |v| @distinct_vars.include?(v) }
              r += "\nGROUP BY "
              case subquery_encoder.execution.dialect.group_by_spec_by
              when "name"
                r += ordered_distinct_vars.map { |v| RuleTranslate.logica_field_to_sql_field(v) }.join(", ")
              when "index"
                selected_fields = @select.keys
                r += ordered_distinct_vars.map { |v| (selected_fields.index(v) + 1).to_s }.join(", ")
              when "expr"
                r += ordered_distinct_vars.map { |k| ql.convert_to_sql_for_group_by(@select[k]) }.join(", ")
              else
                raise "Broken dialect #{subquery_encoder.execution.dialect.name}, group by spec: #{subquery_encoder.execution.dialect.group_by_spec_by}"
              end
            end
          end
          r
        end
      end

      def extract_predicate_structure(c, s)
        predicate = c["predicate_name"]
        if ["<=", "<", ">", ">=", "!=", "&&", "||", "!", "IsNull", "Like", "Constraint", "is", "is not", "~"].include?(predicate)
          s.constraints << { "call" => c }
          return
        end
        table_name = s.allocator.allocate_table(predicate)
        s.tables[table_name] = predicate
        c["record"]["field_value"].each do |field_value|
          table_var = if field_value.key?("except")
                        ExceptExpression.build(table_name, field_value["except"])
          else
                        field_value["field"]
          end
          expr = field_value["value"]["expression"]
          var_name = s.allocator.allocate_var("#{table_name}_#{table_var}")
          s.vars_map[[table_name, table_var]] = var_name
          s.vars_heritage_map[[table_name, table_var]] = expr["expression_heritage"]
          s.inv_vars_map[var_name] = [table_name, table_var]
          s.vars_unification << {
            "left" => { "variable" => { "var_name" => var_name }, "expression_heritage" => expr["expression_heritage"] },
            "right" => expr,
          }
        end
      end

      def extract_inclusion_structure(inclusion, s)
        if inclusion["list"].key?("call") && inclusion["list"]["call"]["predicate_name"] == "Container"
          s.constraints << {
            "call" => {
              "predicate_name" => "In",
              "record" => {
                "field_value" => [
                  { "field" => "left", "value" => { "expression" => inclusion["element"] } },
                  { "field" => "right", "value" => { "expression" => inclusion["list"] } },
                ],
              },
            },
          }
          return
        end
        var_name = s.allocator.allocate_var("unnest_`#{inclusion['element']}`")
        s.vars_map[[nil, var_name]] = var_name
        s.inv_vars_map[var_name] = [nil, var_name]
        s.unnestings << [{ "variable" => { "var_name" => var_name } }, inclusion["list"]]
        s.vars_unification << {
          "left" => inclusion["element"],
          "right" => {
            "call" => {
              "predicate_name" => "ValueOfUnnested",
              "record" => {
                "field_value" => [
                  {
                    "field" => 0,
                    "value" => {
                      "expression" => {
                        "variable" => { "var_name" => var_name, "dont_expand" => true },
                      },
                    },
                  },
                ],
              },
            },
          },
        }
      end

      def extract_conjunctive_structure(conjuncts, s)
        conjuncts.each do |c|
          if c.key?("predicate")
            extract_predicate_structure(c["predicate"], s)
          elsif c.key?("unification")
            if c["unification"]["right_hand_side"].key?("variable") ||
               c["unification"]["left_hand_side"].key?("variable") ||
               c["unification"]["left_hand_side"].key?("record") ||
               c["unification"]["right_hand_side"].key?("record")
              s.vars_unification << {
                "left" => c["unification"]["left_hand_side"],
                "right" => c["unification"]["right_hand_side"],
              }
            else
              if c["unification"]["left_hand_side"] != c["unification"]["right_hand_side"]
                s.constraints << {
                  "call" => {
                    "predicate_name" => "==",
                    "record" => {
                      "field_value" => [
                        { "field" => "left", "value" => { "expression" => c["unification"]["left_hand_side"] } },
                        { "field" => "right", "value" => { "expression" => c["unification"]["right_hand_side"] } },
                      ],
                    },
                  },
                }
              end
            end
          elsif c.key?("inclusion")
            extract_inclusion_structure(c["inclusion"], s)
          elsif c.key?("disjunction")
            raise RuleCompileException.new(
              LogicaRb::Common::Color.format("{warning}Disjunction{end} is disallowed inside of aggregation and negation, please refactor."),
              s.full_rule_text
            )
          else
            raise "Unsupported conjunct: #{c}"
          end
        end
      end

      def has_combine(r)
        member_index = if r.is_a?(Hash)
                         r.keys.sort_by(&:to_s)
        elsif r.is_a?(Array)
                         (0...r.length).to_a
        else
                         raise "HasCombine should be called on list or dict. Got: #{r}"
        end
        if r.is_a?(Hash) && r["predicate_name"] == "Combine"
          return true
        end
        member_index.each do |k|
          if r[k].is_a?(Hash) || r[k].is_a?(Array)
            return true if has_combine(r[k])
          end
        end
        false
      end

      def all_record_fields(record)
        record["field_value"].map { |fv| fv["field"] }
      end

      def inline_predicate_values_recursively(r, names_allocator, conjuncts)
        member_index = if r.is_a?(Hash)
                         r.keys.sort_by(&:to_s)
        elsif r.is_a?(Array)
                         (0...r.length).to_a
        else
                         raise "InlinePredicateValuesRecursively should be called on list or dict."
        end
        member_index.each do |k|
          next if %w[combine type].include?(k)
          inline_predicate_values_recursively(r[k], names_allocator, conjuncts) if r[k].is_a?(Hash) || r[k].is_a?(Array)
        end
        if r.is_a?(Hash) && r.key?("call")
          unless names_allocator.function_exists?(r["call"]["predicate_name"])
            aux_var = names_allocator.allocate_var("inline")
            r_predicate = { "predicate" => LogicaRb::Util.deep_copy(r["call"]) }
            r_predicate["predicate"]["record"]["field_value"] << {
              "field" => "logica_value",
              "value" => { "expression" => { "variable" => { "var_name" => aux_var }, "expression_heritage" => r["expression_heritage"] } },
            }
            r.delete("call")
            r["variable"] = { "var_name" => aux_var }
            conjuncts << r_predicate
          end
        end
      end

      def inline_predicate_values(rule, names_allocator)
        extra_conjuncts = []
        inline_predicate_values_recursively(rule, names_allocator, extra_conjuncts)
        return if extra_conjuncts.empty?
        conjuncts = rule.fetch("body", {}).fetch("conjunction", {}).fetch("conjunct", [])
        conjuncts.concat(extra_conjuncts)
        rule["body"] = { "conjunction" => { "conjunct" => conjuncts } }
      end

      def get_tree_of_combines(rule, tree = nil)
        tree ||= { "rule" => rule, "variables" => Set.new, "subtrees" => [] }
        if rule.is_a?(Array)
          rule.each { |v| tree = get_tree_of_combines(v, tree) }
        elsif rule.is_a?(Hash)
          tree["variables"].add(rule["variable"]["var_name"]) if rule.key?("variable")
          rule.each do |k, v|
            if k != "combine"
              tree = get_tree_of_combines(v, tree)
            else
              subtree = get_tree_of_combines(v)
              tree["subtrees"] << subtree
            end
          end
        end
        tree
      end

      def disambiguate_combine_variables(rule, names_allocator)
        replace = lambda do |tree, outer_variables|
          variables = tree["variables"]
          introduced = variables - outer_variables
          all_vars = variables | outer_variables
          introduced.each do |v|
            next if v.include?("# disambiguated with")
            new_name = "#{v} # disambiguated with #{names_allocator.allocate_var('combine_dis')}"
            replace_variable(v, { "variable" => { "var_name" => new_name } }, tree["rule"])
          end
          tree["subtrees"].each { |s| replace.call(s, all_vars) }
        end
        tree = get_tree_of_combines(rule)
        top_vars = tree["variables"]
        tree["subtrees"].each { |t| replace.call(t, top_vars) }
      end

      def extract_rule_structure(rule, names_allocator = nil, external_vocabulary = nil)
        names_allocator ||= NamesAllocator.new
        rule = LogicaRb::Util.deep_copy(rule)
        if rule["head"]["predicate_name"] != "Combine"
          disambiguate_combine_variables(rule, names_allocator)
        end
        s = RuleStructure.new(names_allocator, external_vocabulary)
        inline_predicate_values(rule, names_allocator)
        s.full_rule_text = rule["full_text"]
        s.this_predicate_name = rule["head"]["predicate_name"]
        s.select, aggregated_vars = head_to_select(rule["head"])
        s.select.each do |k, expr|
          if expr.key?("variable")
            s.vars_unification << {
              "left" => expr,
              "right" => { "variable" => { "var_name" => names_allocator.allocate_var("extract_#{s.this_predicate_name}_#{k}") } },
            }
          end
        end
        if rule.key?("body")
          extract_conjunctive_structure(rule["body"]["conjunction"]["conjunct"], s)
        end
        distinct_denoted = rule.key?("distinct_denoted")
        s.distinct_denoted = distinct_denoted
        if aggregated_vars.any? && !distinct_denoted
          raise RuleCompileException.new(
            LogicaRb::Common::Color.format("Aggregating predicate must be {warning}distinct{end} denoted."),
            s.full_rule_text
          )
        end
        if distinct_denoted
          s.distinct_vars = (s.select.keys.to_set - aggregated_vars.to_set).to_a.sort_by(&:to_s)
        end
        s
      end
    end
  end
end
