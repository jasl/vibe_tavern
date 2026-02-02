# frozen_string_literal: true

require_relative "parser"
require_relative "compiler/universe"
require_relative "plan_builder"
require_relative "compilation"
require_relative "util"
require_relative "errors"

module LogicaRb
  class Transpiler
    SUPPORTED_ENGINES = %w[sqlite psql].freeze
    SUPPORTED_FORMATS = %w[query script plan].freeze

    def self.compile_string(
      source,
      predicate: nil,
      predicates: nil,
      format: :script,
      engine: nil,
      user_flags: {},
      import_root: nil,
      library_profile: nil,
      capabilities: []
    )
      engine = engine&.to_s
      predicates = normalize_predicates(predicate: predicate, predicates: predicates)
      validate_format(format)

      library_profile = normalize_library_profile(library_profile)
      capabilities = normalize_capabilities(capabilities)

      parsed_rules = Parser.parse_file(source, import_root: import_root)["rule"]
      resolved_engine = resolve_engine(parsed_rules, user_flags: user_flags, engine_override: engine)
      unless SUPPORTED_ENGINES.include?(resolved_engine)
        raise UnsupportedEngineError, resolved_engine
      end

      effective_user_flags = user_flags.dup
      rules_for_compile = parsed_rules
      if engine
        effective_user_flags["logica_default_engine"] = resolved_engine
        rules_for_compile = rewrite_engine_annotations(parsed_rules, resolved_engine)
      end

      executions = []
      query_sql_by_predicate = {}
      script_sql_by_predicate = {}

      predicates.each do |predicate|
        program_rules = LogicaRb::Util.deep_copy(rules_for_compile)
        program = Compiler::LogicaProgram.new(program_rules, user_flags: effective_user_flags, library_profile: library_profile)
        formatted_sql = program.formatted_predicate_sql(predicate)
        execution = program.execution

        script_sql_by_predicate[predicate] = normalize_sql_text(formatted_sql)
        query_sql_by_predicate[predicate] = normalize_sql_text(execution.main_predicate_sql)
        executions << execution
      end

      plan = PlanBuilder.from_executions(executions, engine: resolved_engine, final_predicates: predicates)
      plan_by_predicate = predicates.each_with_object({}) { |p, h| h[p] = plan }
      outputs = {
        "query" => join_outputs(predicates.map { |p| query_sql_by_predicate.fetch(p) }),
        "script" => join_outputs(predicates.map { |p| script_sql_by_predicate.fetch(p) }),
        "plan" => plan.to_json(pretty: true),
      }

      functions_used_by_predicate = {}
      relations_used_by_predicate = {}
      functions_used_union = []
      relations_used_union = []

      predicates.each do |p|
        sql = query_sql_by_predicate.fetch(p)
        funcs = LogicaRb::SqlSafety::FunctionAllowlistValidator.scan_functions(sql)
        rels = LogicaRb::SqlSafety::RelationAccessValidator.scan_relations(sql, engine: resolved_engine)

        functions_used_by_predicate[p] = funcs
        relations_used_by_predicate[p] = rels
        functions_used_union.concat(funcs)
        relations_used_union.concat(rels)
      end

      Compilation.new(
        schema_version: "logica_rb.compilation.v1",
        engine: resolved_engine,
        final_predicates: predicates,
        outputs: outputs,
        query_sql_by_predicate: query_sql_by_predicate,
        script_sql_by_predicate: script_sql_by_predicate,
        plan_by_predicate: plan_by_predicate,
        analysis: {
          "functions_used" => functions_used_union.uniq.sort,
          "relations_used" => relations_used_union.uniq.sort,
          "functions_used_by_predicate" => functions_used_by_predicate,
          "relations_used_by_predicate" => relations_used_by_predicate,
        },
        metadata: {
          "import_root" => import_root,
          "user_flags_keys" => effective_user_flags.keys.sort,
          "library_profile" => library_profile.to_s,
          "capabilities" => capabilities.map(&:to_s).sort,
        }
      )
    end

    def self.compile_file(
      path,
      predicate: nil,
      predicates: nil,
      format: :script,
      engine: nil,
      user_flags: {},
      import_root: nil,
      library_profile: nil,
      capabilities: []
    )
      source = File.read(path)
      compile_string(
        source,
        predicate: predicate,
        predicates: predicates,
        format: format,
        engine: engine,
        user_flags: user_flags,
        import_root: import_root,
        library_profile: library_profile,
        capabilities: capabilities
      )
    end

    def self.normalize_predicates(predicate:, predicates:)
      list = predicates.nil? ? predicate : predicates
      list = list.is_a?(Array) ? list : [list]
      list = list.compact.map(&:to_s).reject(&:empty?)
      raise ArgumentError, "predicate(s) must be provided" if list.empty?

      seen = {}
      list.each_with_object([]) do |p, result|
        next if seen.key?(p)
        seen[p] = true
        result << p
      end
    end

    def self.validate_format(format)
      return if SUPPORTED_FORMATS.include?(format.to_s)
      raise InvalidFormatError, "Unknown format: #{format}"
    end

    def self.join_outputs(outputs)
      LogicaRb::Util.join_outputs(outputs)
    end

    def self.normalize_sql_text(text)
      text.to_s.sub(/\n+\z/, "") + "\n"
    end

    def self.resolve_engine(parsed_rules, user_flags:, engine_override: nil)
      return engine_override if engine_override

      default_engine = user_flags.fetch("logica_default_engine", "sqlite")
      annotations = Compiler::Annotations.extract_annotations(parsed_rules, restrict_to: ["@Engine"])
      engines = annotations.fetch("@Engine").keys
      return default_engine if engines.empty?
      if engines.length > 1
        rule_text = annotations["@Engine"].values.first["__rule_text"]
        raise Compiler::RuleTranslate::RuleCompileException.new(
          "Single @Engine must be provided. Provided: #{engines}",
          rule_text
        )
      end
      engines.first
    end

    def self.normalize_library_profile(value)
      profile = (value || :safe).to_sym
      return profile if %i[safe full].include?(profile)

      raise ArgumentError, "Unknown library_profile: #{value.inspect} (expected :safe or :full)"
    end

    def self.normalize_capabilities(value)
      LogicaRb::AccessPolicy.normalize_capabilities(value)
    end

    def self.rewrite_engine_annotations(parsed_rules, engine_override)
      rules = LogicaRb::Util.deep_copy(parsed_rules)
      rules.each do |rule|
        next unless rule.dig("head", "predicate_name") == "@Engine"
        field_values = rule.dig("head", "record", "field_value") || []
        engine_field = field_values.find { |fv| fv["field"] == 0 }
        next unless engine_field

        engine_field["value"] = {
          "expression" => {
            "literal" => {
              "the_string" => { "the_string" => engine_override },
            },
            "expression_heritage" => "\"#{engine_override}\"",
          },
        }
      end
      rules
    end
  end
end
