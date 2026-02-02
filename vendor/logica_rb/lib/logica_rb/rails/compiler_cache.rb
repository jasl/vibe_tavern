# frozen_string_literal: true

require "json"
require "digest"
require "pathname"

module LogicaRb
  module Rails
    class CompilerCache
      def initialize
        @mutex = Mutex.new
        @cache = {}
      end

      def clear!
        @mutex.synchronize { @cache.clear }
        nil
      end

      def fetch(definition, connection:)
        key_data = cache_key_data(definition, connection: connection)
        key = JSON.generate(LogicaRb::Util.sort_keys_recursive(key_data))

        cached = @mutex.synchronize { @cache[key] }
        return cached if cached

        compilation = compile(definition, connection: connection, key_data: key_data)

        @mutex.synchronize { @cache[key] ||= compilation }
      end

      private

      def cache_key_data(definition, connection:)
        engine = resolve_engine(definition.engine, connection: connection)
        import_root = resolve_import_root(definition.import_root || LogicaRb::Rails.configuration.import_root)
        cache_mode = (LogicaRb::Rails.configuration.cache_mode || :mtime).to_sym

        flags = definition.flags || {}
        normalized_flags = flags.transform_keys(&:to_s)

        allow_imports = !!definition.allow_imports
        library_profile = (definition.library_profile || :safe).to_sym
        capabilities = LogicaRb::AccessPolicy.normalize_capabilities(definition.capabilities).map(&:to_s).sort

        base = {
          cache_mode: cache_mode.to_s,
          engine: engine,
          predicate: definition.predicate.to_s,
          format: (definition.format || :query).to_s,
          flags: normalized_flags.sort.to_h,
          import_root: import_root_key(import_root),
          allow_imports: allow_imports,
          library_profile: library_profile.to_s,
          capabilities: capabilities,
          access_policy: definition.access_policy&.cache_key_data(engine: engine),
        }

        if definition.file
          file_path = resolve_logica_file_path(definition.file, import_root: import_root)
          realpath = File.realpath(file_path)

          deps_mtime = dependencies_mtime_for_file(realpath, import_root: import_root, cache_mode: cache_mode, allow_imports: allow_imports)

          base.merge(
            file: realpath,
            dependencies_mtime: deps_mtime
          )
        else
          source_text = definition.source.to_s
          source_sha256 = Digest::SHA256.hexdigest(source_text)
          deps_mtime = dependencies_mtime_for_source(source_text, import_root: import_root, cache_mode: cache_mode, allow_imports: allow_imports)

          base.merge(
            source_sha256: source_sha256,
            dependencies_mtime: deps_mtime
          )
        end
      end

      def compile(definition, connection:, key_data:)
        engine = key_data.fetch(:engine)
        import_root = resolve_import_root(definition.import_root || LogicaRb::Rails.configuration.import_root)
        predicate = definition.predicate.to_s
        flags = (definition.flags || {}).transform_keys(&:to_s)

        allow_imports = !!definition.allow_imports
        library_profile = (definition.library_profile || :safe).to_sym
        capabilities = Array(definition.capabilities)

        compilation =
          if definition.file
            file_path = resolve_logica_file_path(definition.file, import_root: import_root)
            file_path = File.realpath(file_path)
            source_text = File.read(file_path)
            ensure_imports_allowed!(allow_imports: allow_imports, source: source_text)

            LogicaRb::Transpiler.compile_file(
              file_path,
              predicates: predicate,
              engine: engine,
              user_flags: flags,
              import_root: import_root_for_parser(import_root),
              library_profile: library_profile,
              capabilities: capabilities
            )
          else
            source_text = definition.source.to_s
            ensure_imports_allowed!(allow_imports: allow_imports, source: source_text)
            ensure_source_imports_whitelisted!(allow_imports: allow_imports, source: source_text, import_root: import_root_for_parser(import_root))
            if !definition.trusted
              parsed_rules = LogicaRb::Parser.parse_file(source_text, import_root: import_root_for_parser(import_root))["rule"]
              policy_trust = definition.access_policy&.trust || :untrusted
              LogicaRb::SourceSafety::Validator.validate!(parsed_rules, engine: engine, trust: policy_trust, capabilities: capabilities)
            end

            LogicaRb::Transpiler.compile_string(
              source_text,
              predicates: predicate,
              engine: engine,
              user_flags: flags,
              import_root: import_root_for_parser(import_root),
              library_profile: library_profile,
              capabilities: capabilities
            )
          end

        compilation.metadata["dependencies"] = (key_data[:dependencies_mtime] || {}).keys.sort
        compilation
      end

      def resolve_engine(engine, connection:)
        engine = engine.to_s if engine.is_a?(Symbol)
        engine = nil if engine.is_a?(String) && engine.empty?

        return nil if engine.nil?
        return EngineDetector.detect(connection) if engine == "auto"

        engine.to_s
      end

      def resolve_import_root(import_root)
        return nil if import_root.nil?

        if import_root.is_a?(Array)
          import_root.map { |r| r.respond_to?(:to_path) ? r.to_path : r.to_s }
        else
          import_root.respond_to?(:to_path) ? import_root.to_path : import_root.to_s
        end
      end

      def import_root_key(import_root)
        return nil if import_root.nil?
        return import_root.map { |p| File.expand_path(p.to_s) }.sort if import_root.is_a?(Array)

        File.expand_path(import_root.to_s)
      end

      def import_root_for_parser(import_root)
        return "" if import_root.nil?
        return import_root.map(&:to_s) if import_root.is_a?(Array)

        import_root.to_s
      end

      def resolve_logica_file_path(file, import_root:)
        file = file.to_s
        return File.expand_path(file) if Pathname.new(file).absolute?
        return File.expand_path(file) if import_root.nil?

        roots = import_root.is_a?(Array) ? import_root : [import_root]
        roots.each do |root|
          next if root.nil? || root.to_s.empty?
          candidate = File.join(root.to_s, file)
          return File.expand_path(candidate) if File.exist?(candidate)
        end

        File.expand_path(File.join(roots.first.to_s, file))
      end

      def dependencies_mtime_for_file(file_path, import_root:, cache_mode:, allow_imports:)
        mtimes = { file_path => File.mtime(file_path).to_i }
        return mtimes.sort.to_h unless allow_imports
        return mtimes.sort.to_h unless cache_mode == :mtime

        source = File.read(file_path)
        parsed_imports = {}
        LogicaRb::Parser.parse_file(source, import_root: import_root_for_parser(import_root), parsed_imports: parsed_imports)

        dep_paths = parsed_imports.keys.map do |file_import_str|
          resolve_imported_file_path(file_import_str, import_root: import_root_for_parser(import_root))
        end

        all = (dep_paths).uniq
        all.each { |p| mtimes[p] = File.mtime(p).to_i }
        mtimes.sort.to_h
      end

      def dependencies_mtime_for_source(source, import_root:, cache_mode:, allow_imports:)
        return {} unless allow_imports
        return {} unless cache_mode == :mtime

        ensure_source_import_whitelist_configured!(allow_imports: allow_imports)

        parsed_imports = {}
        LogicaRb::Parser.parse_file(source.to_s, import_root: import_root_for_parser(import_root), parsed_imports: parsed_imports)
        ensure_import_prefixes_allowed!(parsed_imports.keys)

        dep_paths = parsed_imports.keys.map do |file_import_str|
          resolve_imported_file_path(file_import_str, import_root: import_root_for_parser(import_root))
        end

        dep_paths.uniq.each_with_object({}) { |p, h| h[p] = File.mtime(p).to_i }.sort.to_h
      end

      def resolve_imported_file_path(file_import_str, import_root:)
        parts = file_import_str.to_s.split(".")

        if import_root.is_a?(Array)
          considered = import_root.map { |root| File.join(root.to_s, File.join(parts) + ".l") }
          existing = considered.find { |p| File.exist?(p) }
          return existing || considered.first
        end

        File.join(import_root.to_s, File.join(parts) + ".l")
      end

      def ensure_imports_allowed!(allow_imports:, source:)
        return nil if allow_imports
        return nil unless imports_present?(source)

        raise ArgumentError, "Imports are disabled (pass trusted: true or allow_imports: true to enable)"
      end

      def ensure_source_imports_whitelisted!(allow_imports:, source:, import_root:)
        return nil unless allow_imports

        ensure_source_import_whitelist_configured!(allow_imports: allow_imports)

        parsed_imports = {}
        LogicaRb::Parser.parse_file(source.to_s, import_root: import_root, parsed_imports: parsed_imports)
        ensure_import_prefixes_allowed!(parsed_imports.keys)
      end

      def ensure_source_import_whitelist_configured!(allow_imports:)
        return nil unless allow_imports

        allowed = LogicaRb::Rails.configuration.allowed_import_prefixes
        allowed_prefixes = Array(allowed).compact.map(&:to_s).map(&:strip).reject(&:empty?)
        return allowed_prefixes unless allowed_prefixes.empty?

        raise ArgumentError, "allowed_import_prefixes must be configured when allow_imports: true for source queries"
      end

      def ensure_import_prefixes_allowed!(import_strs)
        allowed_prefixes = ensure_source_import_whitelist_configured!(allow_imports: true)

        import_strs.each do |import_str|
          ok = allowed_prefixes.any? { |prefix| import_str == prefix || import_str.start_with?("#{prefix}.") }
          next if ok

          raise ArgumentError, "Import path is not allowed: #{import_str}"
        end

        nil
      end

      def imports_present?(source)
        cleaned = LogicaRb::Parser.remove_comments(source.to_s)
        LogicaRb::Parser.split(cleaned, ";").any? { |stmt| stmt.start_with?("import ") }
      rescue LogicaRb::Parser::ParsingException
        false
      end
    end
  end
end
