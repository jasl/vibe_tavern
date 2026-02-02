# frozen_string_literal: true

require "rake"

require_relative "catalog"

namespace :logica_rb do
  desc "Scan app/logica/**/*.l and compile"
  task validate: :environment do
    connection = ::ActiveRecord::Base.connection
    engine = LogicaRb::Rails::EngineDetector.detect(connection)
    catalog = LogicaRb::Rails::Catalog.new

    failures = []

    catalog.files.each do |path|
      predicates = catalog.predicates_for_file(path)
      next if predicates.empty?

      relative = path
      catalog.import_roots.each do |root|
        root = File.expand_path(root.to_s)
        if (path + File::SEPARATOR).start_with?(root + File::SEPARATOR)
          relative = path.delete_prefix(root + File::SEPARATOR)
          break
        end
      end

      begin
        LogicaRb::Transpiler.compile_file(
          path,
          predicates: predicates,
          engine: engine,
          format: :query,
          import_root: catalog.import_roots.length == 1 ? catalog.import_roots.first : catalog.import_roots
        )
        puts "OK #{relative} (#{predicates.join(", ")})"
      rescue StandardError => e
        failures << [relative, e]
        warn "FAIL #{relative}: #{e.class}: #{e.message}"
      end
    end

    if failures.any?
      raise "logica_rb:validate failed (#{failures.length} file(s))"
    end
  end

  desc "Print compiled SQL (format: query|script|plan)"
  task :print, %i[file predicate format] => :environment do |_t, args|
    file = args[:file]
    predicate = args[:predicate]
    format = (args[:format] || "query").to_sym

    raise ArgumentError, "file is required" if file.nil? || file.empty?
    raise ArgumentError, "predicate is required" if predicate.nil? || predicate.empty?

    q = LogicaRb::Rails.query(file: file, predicate: predicate, format: format)

    if format == :plan
      puts q.plan_json(pretty: true)
    else
      puts q.sql(format: format)
    end
  end

  desc "Print predicate signatures (dialect inferred from ActiveRecord adapter)"
  task :signatures, [:file] => :environment do |_t, args|
    file = args[:file]
    raise ArgumentError, "file is required" if file.nil? || file.empty?

    catalog = LogicaRb::Rails::Catalog.new
    path = catalog.resolve_file(file)

    dialect = LogicaRb::Rails::EngineDetector.detect(::ActiveRecord::Base.connection)
    puts LogicaRb::Pipeline.show_signatures(File.read(path), dialect: dialect, import_root: catalog.import_roots.length == 1 ? catalog.import_roots.first : catalog.import_roots)
  end
end
