# frozen_string_literal: true

module LogicaRb
  module Rails
    QueryDefinition = Data.define(
      :name,
      :file,
      :source,
      :predicate,
      :format,
      :engine,
      :flags,
      :as,
      :import_root,
      :trusted,
      :allow_imports,
      :capabilities,
      :library_profile,
      :access_policy
    ) do
      def initialize(
        name:,
        file: nil,
        source: nil,
        predicate:,
        format: :query,
        engine: :auto,
        flags: {},
        as: nil,
        import_root: nil,
        trusted: nil,
        allow_imports: nil,
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
        file = LogicaRb::Util.normalize_optional_string(file)
        source = LogicaRb::Util.normalize_optional_string(source)
        predicate = predicate.to_s
        raise ArgumentError, "predicate must be provided" if predicate.empty?

        if file.nil? && source.nil?
          raise ArgumentError, "Exactly one of file or source must be provided"
        end
        if !file.nil? && !source.nil?
          raise ArgumentError, "file and source are mutually exclusive (provide only one)"
        end

        trusted =
          if trusted.nil?
            file ? true : false
          else
            !!trusted
          end

        format = (format || :query).to_sym

        if source && !trusted && format != :query
          raise ArgumentError, "source queries require format: :query unless trusted: true"
        end

        allow_imports =
          if allow_imports.nil?
            source ? trusted : true
          else
            !!allow_imports
          end

        effective_capabilities =
          if capabilities.nil?
            if !access_policy.nil?
              LogicaRb::Rails.normalize_access_policy(access_policy).effective_capabilities
            elsif source && !trusted
              []
            else
              LogicaRb::Rails.configuration.capabilities
            end
          else
            LogicaRb::Rails.normalize_capabilities(capabilities)
          end

        effective_library_profile =
          if source && !trusted
            :safe
          else
            base = LogicaRb::Rails.configuration.library_profile
            LogicaRb::Rails.normalize_library_profile(library_profile.nil? ? base : library_profile)
          end

        base_policy = LogicaRb::Rails.normalize_access_policy(LogicaRb::Rails.configuration.access_policy)

        merged_policy =
          if access_policy.nil?
            base_policy
          else
            merge_access_policies(base_policy, LogicaRb::Rails.normalize_access_policy(access_policy))
          end

        override_policy =
          if allowed_relations.nil? && allowed_functions.nil? && allowed_schemas.nil? && denied_schemas.nil? && tenant.nil? && timeouts.nil?
            nil
          else
            LogicaRb::AccessPolicy.new(
              allowed_relations: allowed_relations,
              allowed_functions: allowed_functions,
              allowed_schemas: allowed_schemas,
              denied_schemas: denied_schemas,
              tenant: tenant,
              timeouts: timeouts
            )
          end

        merged_policy = merge_access_policies(merged_policy, override_policy) if override_policy

        if source && !trusted && access_policy.nil? && allowed_functions.nil?
          cfg_profile = LogicaRb::Rails.configuration.untrusted_function_profile
          if !cfg_profile.nil? && (merged_policy.nil? || merged_policy.allowed_functions.nil?)
            merged_policy ||= LogicaRb::AccessPolicy.new
            merged_policy = merged_policy.with(function_profile: cfg_profile.to_sym)
          end
        end

        trust_symbol = trusted ? :trusted : :untrusted
        merged_policy ||= LogicaRb::AccessPolicy.new

        effective_policy =
          merged_policy.with(
            trust: trust_symbol,
            capabilities: effective_capabilities
          )

        super(
          name: name&.to_sym,
          file: file,
          source: source,
          predicate: predicate,
          format: format,
          engine: engine,
          flags: flags || {},
          as: as,
          import_root: import_root,
          trusted: trusted,
          allow_imports: allow_imports,
          capabilities: effective_capabilities,
          library_profile: effective_library_profile,
          access_policy: effective_policy
        )
      end

      private

      def merge_access_policies(base, override)
        return override if base.nil?
        return base if override.nil?

        updates = {}
        %i[engine trust capabilities allowed_relations function_profile allowed_functions allowed_schemas denied_schemas tenant timeouts].each do |key|
          value = override.public_send(key)
          next if value.nil?

          updates[key] = value
        end

        updates.empty? ? base : base.with(**updates)
      end
    end
  end
end
