# frozen_string_literal: true

require "pathname"

module LogicaRb
  module Rails
    class Query
      def initialize(definition, connection:, executor: nil, cache: nil)
        @definition = definition
        @connection = connection
        @executor = executor || Executor.new(connection: connection)
        @cache = cache
      end

      attr_reader :definition

      def compile
        cache = @cache || CompilerCache.new
        cache.fetch(@definition, connection: @connection)
      end

      def functions_used
        return @validated_functions_used if @validated_functions_used

        compile.analysis&.fetch("functions_used", nil)
      end

      def relations_used
        return @validated_relations_used if @validated_relations_used

        compile.analysis&.fetch("relations_used", nil)
      end

      def sql(format: :query)
        format = (format || :query).to_sym
        enforce_source_policy!(format: format)
        compilation = compile
        sql_text = compilation.sql(format)
        validate_query_only_sql!(sql_text, engine: compilation.engine, compilation: compilation) if format == :query
        sql_text
      end

      def plan_json(pretty: true)
        enforce_source_policy!(format: :plan)
        compile.plan_json(pretty: pretty)
      end

      def result
        sql_text, engine, compilation = compiled_query_sql_and_engine
        validate_query_only_sql!(sql_text, engine: engine, compilation: compilation)
        @executor.select_all(sql_text, access_policy: @definition.access_policy)
      end

      def records(model:)
        model.find_by_sql(sql(format: :query))
      end

      def relation(model:, as: nil)
        sql_text, engine, compilation = compiled_query_sql_and_engine
        validate_query_only_sql!(sql_text, engine: engine, compilation: compilation)

        alias_name = (as || @definition.as || default_alias_name).to_s

        safe_alias = alias_name.gsub(/[^a-zA-Z0-9_]/, "_")
        subquery = "(#{sql_text.strip})"

        rel = model.from(Arel.sql("#{subquery} AS #{safe_alias}"))
        rel.select("#{safe_alias}.*")
      end

      def cte(name = nil, model: nil, **kwargs)
        name = kwargs.fetch(:name, name)
        raise ArgumentError, "cte name must be provided" if name.nil? || name.to_s.empty?

        cte_name = name.to_sym
        cte_value =
          if model
            relation(model: model, as: cte_name)
          else
            Arel.sql(sql(format: :query))
          end

        { cte_name => cte_value }
      end

      private

      def default_alias_name
        "logica_#{@definition.predicate.to_s.downcase}"
      end

      def enforce_source_policy!(format:)
        return nil unless @definition.source
        return nil if @definition.trusted
        return nil if format.to_sym == :query

        raise ArgumentError, "source queries require format: :query unless trusted: true"
      end

      def compiled_query_sql_and_engine
        enforce_source_policy!(format: :query)
        compilation = compile
        [compilation.sql(:query), compilation.engine, compilation]
      end

      def validate_query_only_sql!(sql, engine:, compilation: nil)
        return nil unless @definition.source
        return nil if @definition.trusted

        return nil if already_validated_query_sql?(sql, engine: engine)

        LogicaRb::SqlSafety::QueryOnlyValidator.validate!(sql, engine: engine, forbidden_functions: [])
        LogicaRb::SqlSafety::ForbiddenFunctionsValidator.validate!(sql, engine: engine)

        policy = @definition.access_policy || LogicaRb::AccessPolicy.untrusted(allowed_relations: [])
        allowed = policy.resolved_allowed_functions(engine: engine)

        functions_used =
          LogicaRb::SqlSafety::FunctionAllowlistValidator.validate!(
            sql,
            engine: engine,
            allowed_functions: allowed
          )

        functions_used_sorted = functions_used.to_a.sort
        @validated_functions_used = functions_used_sorted

        compilation ||= compile
        compilation.analysis&.[]=("functions_used", functions_used_sorted)

        @validated_relations_used =
          LogicaRb::SqlSafety::RelationAccessValidator.validate!(
            sql,
            engine: engine,
            allowed_relations: policy.allowed_relations,
            allowed_schemas: policy.allowed_schemas,
            denied_schemas: policy.effective_denied_schemas(engine: engine)
          )
        @validated_query_sql = sql
        @validated_query_engine = engine.to_s
      end

      def already_validated_query_sql?(sql, engine:)
        return false if @validated_query_sql.nil?
        return false if @validated_query_sql != sql

        # engine can be nil; treat it as "" for comparisons.
        @validated_query_engine.to_s == engine.to_s
      end
    end
  end
end
