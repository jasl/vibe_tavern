#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "set"

# Boot Bundler/Bootsnap without loading full Rails.
require_relative "../../config/boot"

require "agent_core"

require_relative "support/openrouter_models"
require_relative "support/paths"
require_relative "../../lib/agent_core/contrib/token_estimation"

module LlmTokenEstimatorRegistryAudit
  module_function

  DEFAULT_MODELS = VibeTavernEval::OpenRouterModels.ids.freeze

  def run(argv)
    options = parse_options(argv)
    models = normalize_models(options.fetch(:models))

    if models.empty?
      warn "No models selected."
      return 2
    end

    root = VibeTavernEval::Paths.root
    registry = AgentCore::Contrib::TokenEstimation.registry(root: root)
    rows = models.to_a.sort.map { |model| build_row(model: model, registry: registry) }

    print_rows(rows: rows, format: options.fetch(:format), models_source: options.fetch(:models_source))
    print_summary(rows: rows)

    return 1 if options.fetch(:strict) && rows.any? { |row| row.fetch(:status) != "hit" }

    0
  end

  def parse_options(argv)
    opts = {
      models: DEFAULT_MODELS.dup,
      models_source: "openrouter_eval_catalog",
      format: "table",
      strict: false,
    }

    OptionParser.new do |parser|
      parser.banner = "Usage: script/eval/llm_token_estimator_registry_audit.rb [options]"

      parser.on("--models x,y,z", Array, "Model ids to audit (default: OpenRouter eval catalog)") do |list|
        selected = list.map(&:to_s).map(&:strip).reject(&:empty?)
        next if selected.empty?

        opts[:models] = selected
        opts[:models_source] = "cli"
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

  def normalize_models(list)
    Set.new(Array(list).map { |m| m.to_s.strip }.reject(&:empty?))
  end

  def build_row(model:, registry:)
    hint = AgentCore::Contrib::TokenEstimation.canonical_model_hint(model)
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

  def print_rows(rows:, format:, models_source:)
    case format
    when "jsonl"
      rows.each { |row| puts JSON.generate(row) }
    else
      puts "Token Estimator Registry Audit"
      puts "models_source: #{models_source}"
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
