# frozen_string_literal: true

unless ENV["NO_COVERAGE"] == "1"
  require "simplecov"

  SimpleCov.start do
    root File.expand_path("..", __dir__)
    track_files "lib/**/*.rb"

    enable_coverage :branch

    add_group "SqlSafety", "lib/logica_rb/sql_safety"
    add_group "SourceSafety", "lib/logica_rb/source_safety"

    add_filter "/test/"
    add_filter "/dummy/"
  end

  SimpleCov.at_exit do
    result = SimpleCov.result
    result.format!

    # These security coverage gates are meaningful for the full suite, but can
    # cause subset jobs (e.g. DB smoke / DB results) to fail even when tests pass
    # because the security code is loaded but not exercised.
    minimum =
      if ENV.key?("SECURITY_COVERAGE_MIN")
        Integer(ENV.fetch("SECURITY_COVERAGE_MIN"))
      elsif ENV["LOGICA_DB_RESULTS"] == "1" || ENV["LOGICA_DB_SMOKE"] == "1"
        0
      else
        95
      end
    failures = []

    root = File.expand_path("..", __dir__)
    prefixes = {
      "SqlSafety" => File.join(root, "lib/logica_rb/sql_safety/"),
      "SourceSafety" => File.join(root, "lib/logica_rb/source_safety/"),
    }

    if minimum.positive?
      prefixes.each do |group_name, prefix|
        files = result.files.select { |f| f.filename.start_with?(prefix) }
        next if files.empty?

        relevant = 0
        covered = 0
        files.each do |file|
          file.coverage_data.fetch("lines").each do |hits|
            next if hits.nil?
            relevant += 1
            covered += 1 if hits.positive?
          end
        end

        pct = relevant.zero? ? 100.0 : covered * 100.0 / relevant
        failures << "#{group_name} coverage #{pct.round(2)}% < #{minimum}%" if pct < minimum
      end
    end

    unless failures.empty?
      warn failures.join("\n")
      exit 1
    end
  end
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "logica_rb"

require "minitest/autorun"
