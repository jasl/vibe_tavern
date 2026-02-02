# frozen_string_literal: true

require "set"

module LogicaRb
  AccessPolicy = Data.define(
    :engine,
    :trust,
    :capabilities,
    :allowed_relations,
    :function_profile,
    :allowed_functions,
    :allowed_schemas,
    :denied_schemas,
    :tenant,
    :timeouts
  ) do
    def initialize(
      engine: nil,
      trust: nil,
      capabilities: nil,
      allowed_relations: nil,
      function_profile: nil,
      allowed_functions: nil,
      allowed_schemas: nil,
      denied_schemas: nil,
      tenant: nil,
      timeouts: nil
    )
      engine = Util.normalize_optional_string(engine)
      trust = normalize_optional_symbol(trust)
      function_profile = normalize_optional_symbol(function_profile)

      normalized_capabilities =
        if capabilities.nil?
          nil
        else
          self.class.normalize_capabilities(capabilities)
        end

      allowed_relations = normalize_identifier_list(allowed_relations)
      allowed_functions = normalize_allowed_functions(allowed_functions)
      allowed_schemas = normalize_identifier_list(allowed_schemas)
      denied_schemas = normalize_identifier_list(denied_schemas)

      super(
        engine: engine,
        trust: trust,
        capabilities: normalized_capabilities,
        allowed_relations: allowed_relations,
        function_profile: function_profile,
        allowed_functions: allowed_functions,
        allowed_schemas: allowed_schemas,
        denied_schemas: denied_schemas,
        tenant: tenant,
        timeouts: timeouts
      )
    end

    def trusted?
      trust == :trusted
    end

    def untrusted?
      trust == :untrusted
    end

    def cache_key_data(engine: nil)
      resolved_engine = (engine.nil? ? self.engine : Util.normalize_optional_string(engine)).to_s
      resolved_function_profile = resolved_function_profile

      resolved_allowed_functions = resolved_allowed_functions(engine: resolved_engine)
      allowed_functions_key = resolved_allowed_functions.nil? ? nil : resolved_allowed_functions.map(&:to_s).sort

      {
        engine: resolved_engine,
        trust: trust&.to_s,
        capabilities: effective_capabilities.map(&:to_s).sort,
        allowed_relations: Array(allowed_relations).map(&:to_s).sort,
        function_profile: resolved_function_profile&.to_s,
        allowed_functions: allowed_functions_key,
        allowed_schemas: Array(allowed_schemas).map(&:to_s).sort,
        denied_schemas: effective_denied_schemas(engine: resolved_engine).map(&:to_s).sort,
      }
    end

    def self.trusted(engine: nil, function_profile: nil, **kwargs)
      function_profile = :none if function_profile.nil?
      new(**kwargs.merge(engine: engine, trust: :trusted, function_profile: function_profile))
    end

    def self.untrusted(engine: nil, function_profile: nil, **kwargs)
      function_profile = :rails_minimal_plus if function_profile.nil?
      base = { engine: engine, trust: :untrusted, function_profile: function_profile }
      new(**base.merge(kwargs))
    end

    def effective_denied_schemas(engine: nil)
      return denied_schemas if !denied_schemas.nil?

      self.class.default_denied_schemas(engine || self.engine)
    end

    def resolved_allowed_functions(engine: nil)
      resolved_engine = Util.normalize_optional_string(engine) || self.engine

      return resolve_allowed_functions_override(allowed_functions, engine: resolved_engine) if allowed_functions

      case resolved_function_profile
      when :rails_minimal
        LogicaRb::AccessPolicy::RAILS_MINIMAL_ALLOWED_FUNCTIONS
      when :rails_minimal_plus
        LogicaRb::AccessPolicy::RAILS_MINIMAL_PLUS_ALLOWED_FUNCTIONS
      when :none, nil
        nil
      when :custom
        raise ArgumentError, "function_profile is :custom but allowed_functions is not set"
      else
        raise ArgumentError, "Unknown function_profile: #{function_profile.inspect}"
      end
    end

    def effective_capabilities
      return capabilities if !capabilities.nil?

      []
    end

    def self.default_denied_schemas(engine)
      case engine.to_s
      when "psql"
        %w[pg_catalog information_schema]
      when "sqlite"
        %w[sqlite_master sqlite_temp_master]
      else
        %w[pg_catalog information_schema sqlite_master sqlite_temp_master]
      end
    end

    def self.normalize_capabilities(value)
      Array(value)
        .compact
        .map { |c| c.is_a?(Symbol) ? c : c.to_s }
        .map(&:to_s)
        .map(&:strip)
        .reject(&:empty?)
        .map(&:to_sym)
        .uniq
    end

    private

    def normalize_optional_symbol(value)
      return nil if value.nil?

      sym =
        if value.is_a?(String)
          v = value.strip
          return nil if v.empty?

          v.to_sym
        else
          value.to_sym
        end

      sym
    end

    def normalize_identifier_list(value)
      return nil if value.nil?

      list =
        Array(value)
          .compact
          .map(&:to_s)
          .map(&:strip)
          .reject(&:empty?)
          .map(&:downcase)
          .uniq

      list
    end

    def normalize_allowed_functions(value)
      return nil if value.nil?

      if value.is_a?(Hash)
        value.each_with_object({}) do |(k, v), h|
          key = Util.normalize_optional_string(k) || "*"
          key = key.strip.downcase

          list = normalize_identifier_list(v) || []
          h[key] = list.to_set
        end
      else
        (normalize_identifier_list(value) || []).to_set
      end
    end

    def resolved_function_profile
      return function_profile if !function_profile.nil?

      case trust
      when :untrusted
        :rails_minimal_plus
      when :trusted, nil
        :none
      else
        :none
      end
    end
    private :resolved_function_profile

    def resolve_allowed_functions_override(value, engine: nil)
      resolved_engine = Util.normalize_optional_string(engine) || self.engine
      resolved_engine = resolved_engine.to_s.strip.downcase

      if value.is_a?(Hash)
        if value.key?(resolved_engine)
          return value.fetch(resolved_engine)
        end

        if value.key?("*")
          return value.fetch("*")
        end

        if value.key?("all")
          return value.fetch("all")
        end

        return value.values.first if value.length == 1

        return Set.new if resolved_engine.empty?

        return Set.new
      end

      value.to_set
    end
    private :resolve_allowed_functions_override
  end

  AccessPolicy::RAILS_MINIMAL_ALLOWED_FUNCTIONS = Set.new(%w[count sum avg min max]).freeze
  AccessPolicy::RAILS_MINIMAL_PLUS_ALLOWED_FUNCTIONS =
    (AccessPolicy::RAILS_MINIMAL_ALLOWED_FUNCTIONS | Set.new(%w[cast coalesce nullif])).freeze
end
