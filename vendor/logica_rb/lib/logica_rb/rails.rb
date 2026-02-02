# frozen_string_literal: true

require "logica_rb"

begin
  require "active_support/lazy_load_hooks"
  require "active_support/core_ext/class/attribute"
  require "active_support/ordered_options"
rescue LoadError
  raise LogicaRb::MissingOptionalDependencyError.new(
    "activesupport",
    'ActiveSupport is required for logica_rb Rails integration. Add `gem "activesupport"` (or install Rails).'
  )
end

require_relative "rails/configuration"
require_relative "rails/engine_detector"
require_relative "rails/compiler_cache"
require_relative "rails/catalog"
require_relative "rails/executor"
require_relative "rails/query_definition"
require_relative "rails/query"
require_relative "rails/model_dsl"

module LogicaRb
  module Rails
    DEFAULT_CONFIGURATION = Configuration.new(
      import_root: nil,
      cache: true,
      cache_mode: :mtime,
      default_engine: nil,
      allowed_import_prefixes: nil,
      capabilities: [],
      library_profile: :safe,
      untrusted_function_profile: :rails_minimal_plus,
      access_policy: LogicaRb::AccessPolicy.untrusted(allowed_relations: [])
    )

    @configuration = DEFAULT_CONFIGURATION
    @installed = false

    def self.configure
      options = ActiveSupport::OrderedOptions.new
      cfg = @configuration || DEFAULT_CONFIGURATION

      options.import_root = cfg.import_root
      options.cache = cfg.cache
      options.cache_mode = cfg.cache_mode
      options.default_engine = cfg.default_engine
      options.allowed_import_prefixes = cfg.allowed_import_prefixes
      options.capabilities = cfg.capabilities
      options.library_profile = cfg.library_profile
      options.untrusted_function_profile = cfg.untrusted_function_profile
      options.access_policy = cfg.access_policy

      yield options if block_given?

      @configuration = Configuration.new(
        import_root: options.import_root,
        cache: options.cache.nil? ? cfg.cache : !!options.cache,
        cache_mode: (options.cache_mode || cfg.cache_mode || :mtime).to_sym,
        default_engine: options.default_engine&.to_s,
        allowed_import_prefixes: normalize_allowed_import_prefixes(options.allowed_import_prefixes),
        capabilities: options.capabilities.nil? ? cfg.capabilities : normalize_capabilities(options.capabilities),
        library_profile: normalize_library_profile(options.library_profile || cfg.library_profile || :safe),
        untrusted_function_profile: (options.untrusted_function_profile || cfg.untrusted_function_profile || :rails_minimal_plus).to_sym,
        access_policy: options.access_policy.nil? ? cfg.access_policy : normalize_access_policy(options.access_policy)
      )

      clear_cache!
      nil
    end

    def self.configuration
      base = @configuration || DEFAULT_CONFIGURATION

      app_cfg =
        if defined?(::Rails) && ::Rails.respond_to?(:application)
          app = ::Rails.application
          app&.config&.respond_to?(:logica_rb) ? app.config.logica_rb : nil
        end

      return base unless app_cfg

      import_root = app_cfg.respond_to?(:import_root) ? app_cfg.import_root : nil
      import_root = import_root.to_path if import_root.respond_to?(:to_path)

      cache = app_cfg.respond_to?(:cache) ? app_cfg.cache : nil
      cache_mode = app_cfg.respond_to?(:cache_mode) ? app_cfg.cache_mode : nil
      default_engine = app_cfg.respond_to?(:default_engine) ? app_cfg.default_engine : nil
      allowed_import_prefixes = app_cfg.respond_to?(:allowed_import_prefixes) ? app_cfg.allowed_import_prefixes : nil
      capabilities = app_cfg.respond_to?(:capabilities) ? app_cfg.capabilities : nil
      library_profile = app_cfg.respond_to?(:library_profile) ? app_cfg.library_profile : nil
      untrusted_function_profile = app_cfg.respond_to?(:untrusted_function_profile) ? app_cfg.untrusted_function_profile : nil
      access_policy = app_cfg.respond_to?(:access_policy) ? app_cfg.access_policy : nil

      Configuration.new(
        import_root: import_root.nil? ? base.import_root : import_root,
        cache: cache.nil? ? base.cache : !!cache,
        cache_mode: cache_mode.nil? ? base.cache_mode : cache_mode.to_sym,
        default_engine: default_engine.nil? ? base.default_engine : default_engine&.to_s,
        allowed_import_prefixes: allowed_import_prefixes.nil? ? base.allowed_import_prefixes : normalize_allowed_import_prefixes(allowed_import_prefixes),
        capabilities: capabilities.nil? ? base.capabilities : normalize_capabilities(capabilities),
        library_profile: library_profile.nil? ? base.library_profile : normalize_library_profile(library_profile),
        untrusted_function_profile: untrusted_function_profile.nil? ? base.untrusted_function_profile : untrusted_function_profile.to_sym,
        access_policy: access_policy.nil? ? base.access_policy : normalize_access_policy(access_policy)
      )
    end

    def self.normalize_allowed_import_prefixes(value)
      return nil if value.nil?

      Array(value).compact.map(&:to_s).map(&:strip).reject(&:empty?)
    end

    def self.normalize_capabilities(value)
      LogicaRb::AccessPolicy.normalize_capabilities(value)
    end

    def self.normalize_library_profile(value)
      profile = (value || :safe).to_sym
      return profile if %i[safe full].include?(profile)

      raise ArgumentError, "Unknown library_profile: #{value.inspect} (expected :safe or :full)"
    end

    def self.normalize_access_policy(value)
      return nil if value.nil?
      return value if value.is_a?(LogicaRb::AccessPolicy)

      unless value.is_a?(Hash)
        raise ArgumentError, "access_policy must be a LogicaRb::AccessPolicy or Hash, got: #{value.class}"
      end

      normalized = value.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      LogicaRb::AccessPolicy.new(**normalized)
    end

    def self.cache
      @cache ||= CompilerCache.new
    end

    def self.clear_cache!
      return nil unless instance_variable_defined?(:@cache) && @cache

      @cache.clear!
      nil
    end

    def self.install!
      return if @installed

      ActiveSupport.on_load(:active_record) do
        extend LogicaRb::Rails::ModelDSL
      end

      @installed = true
    end

    def self.query(
      file: nil,
      source: nil,
      predicate:,
      connection: nil,
      engine: :auto,
      flags: {},
      format: :query,
      import_root: nil,
      trusted: nil,
      allow_imports: nil,
      as: nil,
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
      connection ||= defined?(::ActiveRecord::Base) ? ::ActiveRecord::Base.connection : nil
      unless connection
        raise LogicaRb::MissingOptionalDependencyError.new(
          "activerecord",
          'ActiveRecord is required for LogicaRb::Rails.query. Add `gem "activerecord"` (or install Rails).'
        )
      end

      definition = QueryDefinition.new(
        name: nil,
        file: file,
        source: source,
        predicate: predicate,
        engine: engine,
        format: format,
        flags: flags,
        as: as,
        import_root: import_root,
        trusted: trusted,
        allow_imports: allow_imports,
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

      cfg = configuration
      cache = cfg.cache ? LogicaRb::Rails.cache : nil
      Query.new(definition, connection: connection, cache: cache)
    end

    def self.cte(name, file: nil, source: nil, predicate:, model: nil, **opts)
      query(file: file, source: source, predicate: predicate, **opts).cte(name, model: model)
    end
  end
end

LogicaRb::Rails.install!

require_relative "rails/railtie" if defined?(::Rails::Railtie)
