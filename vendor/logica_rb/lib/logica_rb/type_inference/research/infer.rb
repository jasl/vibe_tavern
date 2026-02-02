# frozen_string_literal: true

require "json"
require "digest"
require "set"

require_relative "../../common/color"
require_relative "reference_algebra"
require_relative "types_of_builtins"

module LogicaRb
  module TypeInference
    module Research
      module Infer
        class ContextualizedError
          attr_accessor :type_error, :context_string, :refers_to_variable, :refers_to_expression

          def initialize
            @type_error = nil
            @context_string = nil
            @refers_to_variable = nil
            @refers_to_expression = nil
          end

          def replace(type_error, context_string, refers_to_variable, refers_to_expression)
            @type_error = type_error
            @context_string = context_string
            @refers_to_variable = refers_to_variable
            @refers_to_expression = refers_to_expression
          end

          def replace_if_more_useful(type_error, context_string, refers_to_variable, refers_to_expression)
            if @type_error.nil? || @context_string == "UNKNOWN LOCATION" || (@refers_to_variable.nil? && refers_to_variable) || (@refers_to_expression && @refers_to_expression.key?("literal"))
              replace(type_error, context_string, refers_to_variable, refers_to_expression)
            end
          end

          def self.build_nice_message(context_string, error_message)
            [
              LogicaRb::Common::Color.format("{underline}Type analysis:{end}"),
              context_string,
              "",
              LogicaRb::Common::Color.format("[ {error}Error{end} ] ") + error_message,
            ].join("\n")
          end

          def nice_message
            if @type_error.is_a?(Array) && @type_error[0].is_a?(String) && @type_error[0].start_with?("VERBATIM:")
              return @type_error[0].sub("VERBATIM:", "")
            end
            self.class.build_nice_message(@context_string, helpful_error_message)
          end

          def helpful_error_message
            result = @type_error.to_s
            if @refers_to_variable
              result = LogicaRb::Common::Color.format("Variable {warning}%s{end} " % @refers_to_variable) + result
            else
              heritage = @refers_to_expression["expression_heritage"]
              heritage_display = heritage.respond_to?(:display) ? heritage.display : heritage.to_s
              result = LogicaRb::Common::Color.format(
                "Expression {warning}{e}{end} ",
                { e: heritage_display }
              ) + result
            end
            result
          end
        end

        module_function

        def expression_fields
          %w[expression left_hand_side right_hand_side condition consequence otherwise]
        end

        def expressions_iterator(node)
          result = []
          expression_fields.each do |f|
            result << node[f] if node.is_a?(Hash) && node.key?(f)
          end
          if node.is_a?(Hash) && node.key?("constraints")
            result.concat(node["constraints"])
          end
          if node.is_a?(Hash) && node.key?("record") && !node["record"].key?("field_value")
            result << node["record"]
          end
          if node.is_a?(Hash) && node.key?("the_list")
            result.concat(node["the_list"]["element"])
          end
          if node.is_a?(Hash) && node.key?("inclusion")
            result << node["inclusion"]["element"]
            result << node["inclusion"]["list"]
          end
          result
        end

        def walk(node, act)
          if node.is_a?(Array)
            node.each { |v| walk(v, act) }
          elsif node.is_a?(Hash)
            act.call(node)
            node.each do |k, v|
              next if k == "type"
              walk(v, act)
            end
          end
        end

        def act_minding_pod_literals(node)
          Infer.expressions_iterator(node).each do |e|
            next unless e.key?("literal")
            if e["literal"].key?("the_number")
              ReferenceAlgebra.unify(e["type"]["the_type"], ReferenceAlgebra::TypeReference.new("Num"))
            end
            if e["literal"].key?("the_string")
              ReferenceAlgebra.unify(e["type"]["the_type"], ReferenceAlgebra::TypeReference.new("Str"))
            end
            if e["literal"].key?("the_bool")
              ReferenceAlgebra.unify(e["type"]["the_type"], ReferenceAlgebra::TypeReference.new("Bool"))
            end
          end
        end

        def act_clearing_types(node)
          node.delete("type") if node.is_a?(Hash) && node.key?("type")
        end

        def act_remembering_types(node)
          if node.is_a?(Hash) && node.key?("type")
            node["remembered_type"] = JSON.generate(node["type"]["the_type"])
          end
        end

        def act_recalling_types(node)
          return unless node.is_a?(Hash) && node.key?("remembered_type")
          remembered_type = ReferenceAlgebra.revive(JSON.parse(node["remembered_type"]))
          ReferenceAlgebra.unify(node["type"]["the_type"], remembered_type)
        end

        class TypesInferenceEngine
          attr_reader :parsed_rules, :predicate_signature, :collector, :typing_preamble

          def initialize(parsed_rules, dialect)
            @parsed_rules = parsed_rules
            @predicate_argumets_types = {}
            @dependencies = Infer.build_dependencies(@parsed_rules)
            @complexities = Infer.build_complexities(@dependencies)
            @parsed_rules = @parsed_rules.sort_by { |x| @complexities[x["head"]["predicate_name"]] }
            @predicate_signature = TypesOfBuiltins.types_of_builtins
            @typing_preamble = nil
            @collector = nil
            @dialect = dialect
          end

          def collect_types
            collector = TypeCollector.new(@parsed_rules, @dialect)
            collector.collect_types
            @typing_preamble = collector.typing_preamble
            @collector = collector
          end

          def update_types(rule)
            predicate_name = rule["head"]["predicate_name"]
            signature = @predicate_signature[predicate_name] || {}
            if signature.empty?
              rule["head"]["record"]["field_value"].each do |fv|
                signature[fv["field"]] = ReferenceAlgebra::TypeReference.new("Any")
              end
              @predicate_signature[predicate_name] = signature
            end

            rule["head"]["record"]["field_value"].each do |fv|
              field_name = fv["field"]
              v = fv["value"]
              value = v["expression"] || v.dig("aggregation", "expression")
              value_type = value["type"]["the_type"]
              unless signature.key?(field_name)
                raise TypeErrorCaughtException.new(
                  ContextualizedError.build_nice_message(
                    rule["full_text"],
                    LogicaRb::Common::Color.format(
                      "Predicate {warning}%s{end} has inconcistent rules, some include field " % predicate_name
                    ) + LogicaRb::Common::Color.format("{warning}%s{end}" % field_name) + " while others do not."
                  )
                )
              end
              ReferenceAlgebra.unify(signature[field_name], value_type)
            end
          end

          def infer_types
            @parsed_rules.each do |rule|
              next if rule["head"]["predicate_name"].start_with?("@")
              t = TypeInferenceForRule.new(rule, @predicate_signature)
              t.perform_inference
              update_types(rule)
            end
            @parsed_rules.each { |rule| Infer.walk(rule, Infer.method(:concretize_types)) }
            collect_types
          end

          def show_predicate_types
            @predicate_signature.map { |predicate_name, signature| Infer.render_predicate_signature(predicate_name, signature) }.join("\n")
          end
        end

        def concretize_types(node)
          if node.is_a?(Hash) && node.key?("type")
            node["type"]["the_type"] = ReferenceAlgebra.very_concrete_type(node["type"]["the_type"])
          end
        end

        def build_dependencies(rules)
          result = {}
          rules.each do |rule|
            p = rule["head"]["predicate_name"]
            dependencies = []
            extract_predicate_name = lambda do |node|
              dependencies << node["predicate_name"] if node.is_a?(Hash) && node.key?("predicate_name")
            end
            Infer.walk(rule, extract_predicate_name)
            result[p] = ((dependencies.to_set - [p].to_set) | result.fetch(p, []).to_set).to_a
          end
          result
        end

        def build_complexities(dependencies)
          result = {}
          get_complexity = lambda do |p|
            return 0 unless dependencies.key?(p)
            unless result.key?(p)
              result[p] = 1
              result[p] = 1 + dependencies[p].sum { |x| get_complexity.call(x) }
            end
            result[p]
          end
          dependencies.each_key { |p| get_complexity.call(p) }
          result
        end

        class TypeInferenceForRule
          def initialize(rule, types_of_builtins)
            @rule = rule
            @variable_type = {}
            @type_id_counter = 0
            @found_error = nil
            @types_of_builtins = types_of_builtins
          end

          def perform_inference
            init_types
            mind_pod_literals
            mind_builtin_field_types
            iterate_inference
          end

          def get_type_id
            result = @type_id_counter
            @type_id_counter += 1
            result
          end

          def act_initializing_types(node)
            Infer.expressions_iterator(node).each do |e|
              next if e.key?("variable")
              e["type"] = { "the_type" => ReferenceAlgebra::TypeReference.new("Any"), "type_id" => get_type_id }
            end
          end

          def init_types
            Infer.walk_initializing_variables(@rule, method(:get_type_id))
            Infer.walk(@rule, method(:act_initializing_types))
          end

          def mind_pod_literals
            Infer.walk(@rule, Infer.method(:act_minding_pod_literals))
          end

          def act_minding_builtin_field_types(node)
            instill_types = lambda do |predicate_name, field_value, signature, output_value|
              copier = ReferenceAlgebra::TypeStructureCopier.new
              copy = copier.method(:copy_concrete_or_reference_type)
              if output_value
                output_value_type = output_value["type"]["the_type"]
                if signature.key?("logica_value")
                  ReferenceAlgebra.unify(output_value_type, copy.call(signature["logica_value"]))
                else
                  error_message = ContextualizedError.build_nice_message(
                    output_value["expression_heritage"].display,
                    "Predicate %s is not a function, but was called as such." % LogicaRb::Common::Color.format("{warning}%s{end}") % predicate_name
                  )
                  error = ReferenceAlgebra::BadType.new(["VERBATIM:#{error_message}", output_value_type.target])
                  output_value_type.target = ReferenceAlgebra::TypeReference.to(error)
                end
              end

              field_value.each do |fv|
                field_name = fv["field"]
                if !signature.key?(field_name) && field_name.is_a?(Integer) && signature.key?("col#{field_name}")
                  field_name = "col#{field_name}"
                end
                if signature.key?(field_name)
                  ReferenceAlgebra.unify(fv["value"]["expression"]["type"]["the_type"], copy.call(signature[field_name]))
                elsif field_name == "*"
                  args = copy.call(ReferenceAlgebra::ClosedRecord[signature])
                  ReferenceAlgebra.unify(fv["value"]["expression"]["type"]["the_type"], ReferenceAlgebra::TypeReference.to(args))
                elsif signature.key?("*")
                  args = copy.call(signature["*"])
                  ReferenceAlgebra.unify_record_field(args, field_name, fv["value"]["expression"]["type"]["the_type"])
                  if args.target.is_a?(ReferenceAlgebra::BadType)
                    error_message = ContextualizedError.build_nice_message(
                      fv["value"]["expression"]["expression_heritage"].display,
                      "Predicate %s does not have argument %s, but it was addressed." %
                        [LogicaRb::Common::Color.format("{warning}%s{end}") % predicate_name,
                         LogicaRb::Common::Color.format("{warning}%s{end}") % fv["field"]]
                    )
                    error = ReferenceAlgebra::BadType.new(["VERBATIM:#{error_message}", fv["value"]["expression"]["type"]["the_type"].target])
                    fv["value"]["expression"]["type"]["the_type"].target = ReferenceAlgebra::TypeReference.to(error)
                  end
                else
                  error_message = ContextualizedError.build_nice_message(
                    fv["value"]["expression"]["expression_heritage"].display,
                    "Predicate %s does not have argument %s, but it was addressed." %
                      [LogicaRb::Common::Color.format("{warning}%s{end}") % predicate_name,
                       LogicaRb::Common::Color.format("{warning}%s{end}") % fv["field"]]
                  )
                  error = ReferenceAlgebra::BadType.new(["VERBATIM:#{error_message}", fv["value"]["expression"]["type"]["the_type"].target])
                  fv["value"]["expression"]["type"]["the_type"].target = ReferenceAlgebra::TypeReference.to(error)
                end
              end
            end

            Infer.expressions_iterator(node).each do |e|
              next unless e.key?("call")
              p = e["call"]["predicate_name"]
              if @types_of_builtins.key?(p)
                instill_types.call(p, e["call"]["record"]["field_value"], @types_of_builtins[p], e)
              end
            end

            if node.is_a?(Hash) && node.key?("predicate")
              p = node["predicate"]["predicate_name"]
              if @types_of_builtins.key?(p)
                instill_types.call(p, node["predicate"]["record"]["field_value"], @types_of_builtins[p], nil)
              end
            end

            if node.is_a?(Hash) && node.key?("head")
              p = node["head"]["predicate_name"]
              if @types_of_builtins.key?(p)
                instill_types.call(p, node["head"]["record"]["field_value"], @types_of_builtins[p], nil)
              end
            end
          end

          def mind_builtin_field_types
            Infer.walk(@rule, method(:act_minding_builtin_field_types))
          end

          def act_unifying(node)
            if node.is_a?(Hash) && node.key?("unification")
              left_type = node["unification"]["left_hand_side"]["type"]["the_type"]
              right_type = node["unification"]["right_hand_side"]["type"]["the_type"]
              ReferenceAlgebra.unify(left_type, right_type)
            end
          end

          def act_understanding_subscription(node)
            if node.is_a?(Hash) && node.key?("subscript") && node["subscript"].key?("record")
              record_type = node["subscript"]["record"]["type"]["the_type"]
              field_type = node["type"]["the_type"]
              field_name = node["subscript"]["subscript"]["literal"]["the_symbol"]["symbol"]
              ReferenceAlgebra.unify_record_field(record_type, field_name, field_type)
            end
          end

          def act_minding_record_literals(node)
            return unless node.is_a?(Hash) && node.key?("type") && node.key?("record")
            record_type = node["type"]["the_type"]
            ReferenceAlgebra.unify(record_type, ReferenceAlgebra::TypeReference.new(ReferenceAlgebra::OpenRecord.new))
            node["record"]["field_value"].each do |fv|
              field_type = fv["value"]["expression"]["type"]["the_type"]
              field_name = fv["field"]
              ReferenceAlgebra.unify_record_field(record_type, field_name, field_type)
            end
            node["type"]["the_type"].close_record
          end

          def act_minding_typing_predicate_literals(node)
            if node.is_a?(Hash) && node.key?("type") && node.dig("literal", "the_predicate")
              predicate_name = node["literal"]["the_predicate"]["predicate_name"]
              if %w[Str Num Bool Time].include?(predicate_name)
                ReferenceAlgebra.unify(node["type"]["the_type"], ReferenceAlgebra::TypeReference.new(predicate_name))
              end
            end
          end

          def act_minding_list_literals(node)
            if node.is_a?(Hash) && node.key?("type") && node.dig("literal", "the_list")
              list_type = node["type"]["the_type"]
              node["literal"]["the_list"]["element"].each do |e|
                ReferenceAlgebra.unify_list_element(list_type, e["type"]["the_type"])
              end
              ReferenceAlgebra.unify_list_element(list_type, ReferenceAlgebra::TypeReference.new("Any"))
            end
          end

          def act_minding_inclusion(node)
            if node.is_a?(Hash) && node.key?("inclusion")
              list_type = node["inclusion"]["list"]["type"]["the_type"]
              element_type = node["inclusion"]["element"]["type"]["the_type"]
              ReferenceAlgebra.unify_list_element(list_type, element_type)
            end
          end

          def act_minding_combine(node)
            if node.is_a?(Hash) && node.key?("combine")
              field_value = node["combine"]["head"]["record"]["field_value"]
              logica_value = field_value.find { |fv| fv["field"] == "logica_value" }["value"]
              ReferenceAlgebra.unify(node["type"]["the_type"], logica_value["aggregation"]["expression"]["type"]["the_type"])
            end
          end

          def act_minding_implications(node)
            if node.is_a?(Hash) && node.key?("implication")
              node["implication"]["if_then"].each do |if_then|
                ReferenceAlgebra.unify(node["type"]["the_type"], if_then["consequence"]["type"]["the_type"])
              end
              ReferenceAlgebra.unify(node["type"]["the_type"], node["implication"]["otherwise"]["type"]["the_type"])
            end
          end

          def iterate_inference
            Infer.walk(@rule, method(:act_minding_typing_predicate_literals))
            Infer.walk(@rule, method(:act_minding_record_literals))
            Infer.walk(@rule, method(:act_unifying))
            Infer.walk(@rule, method(:act_understanding_subscription))
            Infer.walk(@rule, method(:act_minding_list_literals))
            Infer.walk(@rule, method(:act_minding_inclusion))
            Infer.walk(@rule, method(:act_minding_combine))
            Infer.walk(@rule, method(:act_minding_implications))
          end
        end

        def render_predicate_signature(predicate_name, signature)
          field_value = lambda do |f, v|
            field = f.is_a?(Integer) ? "" : "#{f}: "
            value = ReferenceAlgebra.render_type(ReferenceAlgebra.very_concrete_type(v))
            field + value
          end
          field_values = signature.map { |f, v| field_value.call(f, v) }.reject { |f| f.start_with?("logica_value") }
          signature_str = field_values.join(", ")
          maybe_value = signature.select { |f, _| f == "logica_value" }.map do |_f, v|
            " = " + ReferenceAlgebra.render_type(ReferenceAlgebra.very_concrete_type(v))
          end
          value_or_nothing = maybe_value[0] || ""
          "type #{predicate_name}(#{signature_str})#{value_or_nothing};"
        end

        class TypeInferenceForStructure
          attr_reader :collector, :quazy_rule

          def initialize(structure, signatures, dialect:)
            @structure = structure
            @signatures = signatures
            @collector = nil
            @quazy_rule = nil
            @dialect = dialect
          end

          def perform_inference
            quazy_rule = build_quazy_rule
            @quazy_rule = quazy_rule
            Infer.walk(quazy_rule, Infer.method(:act_remembering_types))
            Infer.walk(quazy_rule, Infer.method(:act_clearing_types))
            inferencer = TypeInferenceForRule.new(quazy_rule, @signatures)
            inferencer.perform_inference
            Infer.walk(quazy_rule, Infer.method(:act_recalling_types))

            Infer.walk(quazy_rule, Infer.method(:concretize_types))
            collector = TypeCollector.new([quazy_rule], @dialect)
            collector.collect_types
            @collector = collector
          end

          def build_quazy_rule
            {
              "quazy_body" => build_quazy_body,
              "select" => build_select,
              "unnestings" => build_unnestings,
              "constraints" => @structure.constraints,
            }
          end

          def build_unnestings
            @structure.unnestings.map do |variable, the_list|
              { "inclusion" => { "element" => variable, "list" => the_list } }
            end
          end

          def build_quazy_body
            calls = {}
            @structure.tables.each do |table_id, predicate|
              calls[table_id] = { "predicate" => { "predicate_name" => predicate, "record" => { "field_value" => [] } } }
            end
            @structure.vars_map.each do |(table_id, field), variable|
              next if table_id.nil?
              heritage = @structure.vars_heritage_map.fetch([table_id, field], "UNKNOWN_LOCATION")
              calls[table_id]["predicate"]["record"]["field_value"] << {
                "field" => field,
                "value" => { "expression" => { "variable" => { "var_name" => variable }, "expression_heritage" => heritage } },
              }
            end
            calls.values
          end

          def build_select
            field_values = []
            result = { "record" => { "field_value" => field_values } }
            @structure.select.each do |k, v|
              field_values << { "field" => k, "value" => { "expression" => v } }
            end
            result
          end
        end

        class TypeErrorCaughtException < StandardError
          def show_message(stream = $stderr)
            stream.puts(to_s)
          end
        end

        class TypeErrorChecker
          def initialize(typed_rules)
            @typed_rules = typed_rules
          end

          def check_for_error(mode = "print")
            found_error = search_type_errors
            if found_error.type_error
              if mode == "print"
                puts(found_error.nice_message)
              elsif mode == "raise"
                raise TypeErrorCaughtException.new(found_error.nice_message)
              else
                raise "Unknown mode"
              end
            end
          end

          def search_type_errors
            found_error = ContextualizedError.new
            look_for_error = lambda do |node|
              if node.is_a?(Hash) && node.key?("type")
                t = ReferenceAlgebra.very_concrete_type(node["type"]["the_type"])
                if t.is_a?(ReferenceAlgebra::BadType)
                  v = node.dig("variable", "var_name")
                  if node.key?("expression_heritage")
                    found_error.replace_if_more_useful(t, node["expression_heritage"].display, v, node)
                  else
                    found_error.replace_if_more_useful(t, "UNKNOWN LOCATION", v, node)
                  end
                end
              end
            end
            @typed_rules.each do |rule|
              Infer.walk(rule, look_for_error)
              return found_error if found_error.type_error
            end
            found_error
          end
        end

        def walk_initializing_variables(node, get_type)
          type_of_variable = {}
          jog = lambda do |n, found_combines|
            if n.is_a?(Array)
              n.each { |v| jog.call(v, found_combines) }
            elsif n.is_a?(Hash)
              if n.key?("variable")
                var_name = n["variable"]["var_name"]
                type_of_variable[var_name] ||= { "the_type" => ReferenceAlgebra::TypeReference.new("Any"), "type_id" => get_type.call }
                n["type"] = type_of_variable[var_name]
              end
              n.each do |k, v|
                next if k == "type"
                if k != "combine"
                  jog.call(v, found_combines)
                else
                  found_combines << v
                end
              end
            end
          end
          jog_predicate = lambda do |n|
            found_combines = []
            jog.call(n, found_combines)
            backed_up = type_of_variable.dup
            found_combines.each do |combine|
              jog_predicate.call(combine)
              type_of_variable = backed_up
            end
          end
          jog_predicate.call(node)
        end

        def fingerprint(s)
          Digest::MD5.hexdigest(s.to_s)[0, 16].to_i(16)
        end

        def record_type_name(type_render)
          "logicarecord#{fingerprint(type_render) % 1_000_000_000}"
        end

        class TypeCollector
          attr_reader :definitions, :typing_preamble, :psql_type_cache

          def initialize(parsed_rules, dialect)
            @parsed_rules = parsed_rules
            @type_map = {}
            @psql_struct_type_name = {}
            @psql_type_definition = {}
            @definitions = []
            @typing_preamble = ""
            @psql_type_cache = {}
            @dialect = dialect
          end

          def act_populating_type_map(node)
            return unless node.is_a?(Hash) && node.key?("type")
            t = node["type"]["the_type"]
            t_rendering = ReferenceAlgebra.render_type(t)
            @type_map[t_rendering] = t
            node["type"]["rendered_type"] = t_rendering
            if node.key?("combine") && ReferenceAlgebra.fully_defined?(t)
              node["type"]["combine_psql_type"] = psql_type(t)
            end
            if ReferenceAlgebra.fully_defined?(t)
              @psql_type_cache[t_rendering] = psql_type(t)
            end
            if t.is_a?(Hash) && ReferenceAlgebra.fully_defined?(t)
              node["type"]["type_name"] = Infer.record_type_name(t_rendering)
            end
            if t.is_a?(Array) && ReferenceAlgebra.fully_defined?(t)
              e = t[0]
              node["type"]["element_type_name"] = psql_type(e)
            end
          end

          def collect_types
            Infer.walk(@parsed_rules, method(:act_populating_type_map))
            @type_map.each_key do |t|
              the_type = @type_map[t]
              if the_type.is_a?(Hash)
                next unless ReferenceAlgebra.fully_defined?(the_type)
                @psql_struct_type_name[t] = Infer.record_type_name(t)
              end
            end
            build_psql_definitions
          end

          def psql_type(t)
            return "text" if t == "Str"
            if t == "Num"
              return "float" if @dialect == "duckdb"
              return "numeric"
            end
            return "bool" if t == "Bool"
            return "timestamp" if t == "Time"
            return Infer.record_type_name(ReferenceAlgebra.render_type(t)) if t.is_a?(Hash)
            return psql_type(t[0]) + "[]" if t.is_a?(Array)
            raise t.to_s
          end

          def build_psql_definitions
            @psql_struct_type_name.each_key do |t|
              arg_name = lambda { |x| x == "cast" ? '"cast"' : (x.is_a?(String) ? x : "col#{x}") }
              args = @type_map[t].sort_by { |kv| ReferenceAlgebra.str_int_key(kv) }.map do |f, v|
                "#{arg_name.call(f)} #{psql_type(v)}"
              end.join(", ")
              dialect_interjection = @dialect == "duckdb" ? "struct" : ""
              @psql_type_definition[t] = "create type #{@psql_struct_type_name[t]} as #{dialect_interjection}(#{args});"
            end
            wrap = if %w[psql sqlite bigquery].include?(@dialect)
                     lambda do |n, d|
                       "-- Logica type: #{n}\nif not exists (select 'I(am) :- I(think)' from pg_type where typname = '#{n}') then #{d} end if;"
                     end
            elsif @dialect == "duckdb"
                     lambda { |n, d| "-- Logica type: #{n}\ndrop type if exists #{n} cascade; #{d}\n" }
            else
                     raise "Unknown psql dialect: #{@dialect}"
            end
            @definitions = @psql_struct_type_name.keys.sort_by(&:length).each_with_object({}) do |t, h|
              next if @psql_struct_type_name[t] == "logicarecord893574736"
              h[t] = wrap.call(@psql_struct_type_name[t], @psql_type_definition[t])
            end
            @typing_preamble = Infer.build_preamble(@definitions, @dialect)
          end
        end

        def build_preamble(definitions, dialect)
          if dialect.is_a?(Hash) && dialect.key?(:dialect)
            dialect = dialect[:dialect]
          end
          ordered_definitions = definitions.keys.sort_by(&:length).map { |k| definitions[k] }
          if %w[psql sqlite bigquery].include?(dialect)
            "DO $$\nBEGIN\n#{ordered_definitions.join("\n")}\nEND $$;\n"
          elsif dialect == "duckdb"
            ordered_definitions.join("\n")
          else
            raise "Unknown psql dialect: #{dialect}"
          end
        end

        def argument_names(signature)
          signature.keys.map { |v| v.is_a?(Integer) ? "col#{v}" : v }
        end
      end
    end
  end
end
