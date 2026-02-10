#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "set"

ENV["RAILS_ENV"] ||= "development"
require_relative "../config/environment"

module LlmTokenEstimatorRegistryAudit
  module_function

  DEFAULT_SCRIPT_PATHS = [
    "script/llm_directives_eval.rb",
    "script/llm_tool_call_eval.rb",
    "script/llm_language_policy_eval.rb",
  ].freeze

  def run(argv)
    options = parse_options(argv)
    scripts = resolve_script_paths(options.fetch(:scripts))
    models = collect_models(scripts: scripts)

    if models.empty?
      warn "No models found in: #{scripts.join(", ")}"
      return 2
    end

    registry = TavernKit::VibeTavern::TokenEstimation.registry(root: Rails.root)
    rows = models.to_a.sort.map { |model| build_row(model: model, registry: registry) }

    print_rows(rows: rows, format: options.fetch(:format), scripts: scripts)
    print_summary(rows: rows)

    return 1 if options.fetch(:strict) && rows.any? { |row| row.fetch(:status) != "hit" }

    0
  end

  def parse_options(argv)
    opts = {
      scripts: DEFAULT_SCRIPT_PATHS.dup,
      format: "table",
      strict: false,
    }

    OptionParser.new do |parser|
      parser.banner = "Usage: script/llm_token_estimator_registry_audit.rb [options]"

      parser.on("--scripts x,y,z", Array, "Script paths to scan for model declarations") do |list|
        opts[:scripts] = list.map(&:to_s).map(&:strip).reject(&:empty?)
      end

      parser.on("--format FORMAT", "Output format: table|jsonl") do |value|
        format = value.to_s.strip.downcase
        raise OptionParser::InvalidArgument, value unless %w[table jsonl].include?(format)

        opts[:format] = format
      end

      parser.on("--strict", "Exit non-zero when any model misses registry or tokenizer file") do
        opts[:strict] = true
      end

      parser.on("-h", "--help", "Show help") do
        puts parser
        exit 0
      end
    end.parse!(argv)

    opts
  end

  def resolve_script_paths(paths)
    Array(paths).map do |path|
      expanded = Pathname.new(path.to_s)
      expanded = Rails.root.join(expanded) if expanded.relative?
      expanded.cleanpath
    end
  end

  def collect_models(scripts:)
    models = Set.new

    scripts.each do |path|
      unless path.exist?
        warn "Missing script: #{path}"
        next
      end

      path.each_line do |line|
        next unless line =~ /model\s+"([^"]+)"/

        models << Regexp.last_match(1).to_s
      end
    end

    models
  end

  def build_row(model:, registry:)
    hint = TavernKit::VibeTavern::TokenEstimation.canonical_model_hint(model)
    entry = registry[hint]

    return { model: model, hint: hint, status: "miss" } unless entry.is_a?(Hash)

    family = entry[:tokenizer_family].to_s
    path = entry[:tokenizer_path].to_s.strip
    source_hint = entry[:source_hint].to_s.strip
    source_repo = entry[:source_repo].to_s.strip

    path_exists = path.empty? ? nil : File.exist?(path)
    status = path_exists == false ? "missing_file" : "hit"

    {
      model: model,
      hint: hint,
      status: status,
      tokenizer_family: family,
      tokenizer_path: path.empty? ? nil : path,
      tokenizer_path_exists: path_exists,
      source_hint: source_hint.empty? ? nil : source_hint,
      source_repo: source_repo.empty? ? nil : source_repo,
    }
  end

  def print_rows(rows:, format:, scripts:)
    case format
    when "jsonl"
      rows.each { |row| puts JSON.generate(row) }
    else
      puts "Token Estimator Registry Audit"
      puts "scripts: #{scripts.join(", ")}"
      puts "rows: #{rows.size}"
      puts

      header = %w[status model hint family source_hint source_repo path_exists tokenizer_path]
      puts header.join("\t")

      rows.each do |row|
        puts [
          row.fetch(:status),
          row.fetch(:model),
          row.fetch(:hint),
          row.fetch(:tokenizer_family, "-"),
          row.fetch(:source_hint, "-"),
          row.fetch(:source_repo, "-"),
          row.fetch(:tokenizer_path_exists, "-"),
          row.fetch(:tokenizer_path, "-"),
        ].join("\t")
      end
    end
  end

  def print_summary(rows:)
    counts = rows.group_by { |row| row.fetch(:status) }.transform_values(&:size)
    hit = counts.fetch("hit", 0)
    miss = counts.fetch("miss", 0)
    missing_file = counts.fetch("missing_file", 0)

    warn "summary: hit=#{hit} miss=#{miss} missing_file=#{missing_file}"
  end
end

exit LlmTokenEstimatorRegistryAudit.run(ARGV)
