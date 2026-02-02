# frozen_string_literal: true

module LogicaRb
  module Rails
    module ModelDSL
      def self.extended(base)
        base.class_attribute :logica_queries, default: {}, instance_accessor: false
      end

      def logica_query(
        name,
        file:,
        predicate:,
        engine: :auto,
        format: :query,
        flags: {},
        as: nil,
        import_root: nil,
        capabilities: nil,
        library_profile: nil,
        access_policy: nil,
        allowed_relations: nil,
        allowed_functions: nil,
        allowed_schemas: nil,
        denied_schemas: nil,
        tenant: nil,
        timeouts: nil
      )
        name = name.to_sym

        definition = QueryDefinition.new(
          name: name,
          file: file,
          predicate: predicate,
          engine: engine,
          format: format,
          flags: flags,
          as: as,
          import_root: import_root,
          capabilities: capabilities,
          library_profile: library_profile,
          access_policy: access_policy,
          allowed_relations: allowed_relations,
          allowed_functions: allowed_functions,
          allowed_schemas: allowed_schemas,
          denied_schemas: denied_schemas,
          tenant: tenant,
          timeouts: timeouts
        )

        self.logica_queries = logica_queries.merge(name => definition)
        definition
      end

      def logica(name, connection: nil, **overrides)
        name = name.to_sym
        base_definition = logica_queries.fetch(name) { raise ArgumentError, "Unknown logica query: #{name}" }

        connection ||= ActiveRecord::Base.connection
        cfg = LogicaRb::Rails.configuration

        resolved_import_root =
          if overrides.key?(:import_root)
            overrides[:import_root]
          else
            base_definition.import_root || cfg.import_root
          end

        resolved_engine = resolve_engine(
          overrides.key?(:engine) ? overrides[:engine] : base_definition.engine,
          connection: connection,
          cfg: cfg
        )

        resolved_flags = (base_definition.flags || {}).merge(overrides[:flags] || {})

        definition = QueryDefinition.new(
          name: base_definition.name,
          file: overrides.fetch(:file, base_definition.file),
          source: overrides.fetch(:source, base_definition.source),
          predicate: overrides.fetch(:predicate, base_definition.predicate),
          format: overrides.fetch(:format, base_definition.format || :query).to_sym,
          engine: resolved_engine,
          flags: resolved_flags,
          as: overrides.fetch(:as, base_definition.as),
          import_root: resolved_import_root,
          trusted: overrides.fetch(:trusted, base_definition.trusted),
          allow_imports: overrides.fetch(:allow_imports, base_definition.allow_imports),
          capabilities: overrides.fetch(:capabilities, base_definition.capabilities),
          library_profile: overrides.fetch(:library_profile, base_definition.library_profile),
          access_policy: overrides.fetch(:access_policy, base_definition.access_policy),
          allowed_relations: overrides.fetch(:allowed_relations, nil),
          allowed_functions: overrides.fetch(:allowed_functions, nil),
          allowed_schemas: overrides.fetch(:allowed_schemas, nil),
          denied_schemas: overrides.fetch(:denied_schemas, nil),
          tenant: overrides.fetch(:tenant, nil),
          timeouts: overrides.fetch(:timeouts, nil)
        )

        cache = cfg.cache ? LogicaRb::Rails.cache : nil

        Query.new(
          definition,
          connection: connection,
          executor: Executor.new(connection: connection),
          cache: cache
        )
      end

      def logica_sql(name, **opts)
        logica(name, **opts).sql
      end

      def logica_result(name, **opts)
        logica(name, **opts).result
      end

      def logica_relation(name, **opts)
        logica(name, **opts).relation(model: self)
      end

      def logica_records(name, **opts)
        logica(name, **opts).records(model: self)
      end

      private

      def resolve_engine(engine, connection:, cfg:)
        engine = engine.to_sym if engine.is_a?(String) && !engine.empty?

        resolved =
          case engine
          when nil, :auto
            cfg.default_engine&.to_s || EngineDetector.detect(connection)
          else
            engine.to_s
          end

        resolved
      end
    end
  end
end
