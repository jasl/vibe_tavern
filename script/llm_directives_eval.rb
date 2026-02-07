#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "thread"
require "time"

require_relative "openrouter_sampling_profiles"

# Default settings
ENV["RAILS_ENV"] ||= "development"

# Load Rails environment
require_relative "../config/environment"

module DirectivesEval
  class ModelCatalog
    Entry = Struct.new(:id, :workarounds, :tags, keyword_init: true) do
      def initialize(id:, workarounds: [], tags: [])
        super(
          id: id.to_s,
          workarounds: normalize_workarounds(workarounds),
          tags: normalize_tags(tags),
        )
      end

      def base_id
        id.split(":", 2).first.to_s
      end

      def provider
        base_id.split("/", 2).first.to_s
      end

      def matches?(raw_token)
        token = raw_token.to_s.strip.downcase
        return false if token.empty?

        candidates = ([id, base_id, provider] + tags).map(&:to_s).map(&:downcase).uniq

        if token.include?("*")
          candidates.any? { |value| File.fnmatch(token, value) }
        else
          candidates.include?(token)
        end
      end

      private

      def normalize_workarounds(value)
        Array(value).map { |item| item.to_s.strip.downcase.tr("-", "_").to_sym }.uniq
      end

      def normalize_tags(value)
        Array(value).map { |item| item.to_s.strip.downcase }.reject(&:empty?).uniq
      end
    end

    def self.build(&block)
      catalog = new
      catalog.instance_eval(&block) if block
      catalog.freeze
    end

    def initialize
      @entries = []
    end

    def model(id, workarounds: [], tags: [])
      entry = Entry.new(id: id, workarounds: workarounds, tags: tags)
      @entries << entry
      entry
    end

    def ids
      @entries.map(&:id)
    end

    def filter(raw_filter)
      tokens = raw_filter.to_s.split(",").map(&:strip).reject(&:empty?)
      return @entries.dup if tokens.empty? || tokens.any? { |token| %w[all full *].include?(token.downcase) }

      include_tokens = tokens.reject { |token| token.start_with?("!") }
      exclude_tokens = tokens.select { |token| token.start_with?("!") }.map { |t| t.delete_prefix("!") }.reject(&:empty?)

      selected =
        if include_tokens.empty?
          @entries
        else
          @entries.select { |entry| include_tokens.any? { |token| entry.matches?(token) } }
        end

      selected.reject { |entry| exclude_tokens.any? { |token| entry.matches?(token) } }
    end
  end

  module ModelWorkarounds
    module_function

    def presets_for(model_entry, exclude: [])
      excluded =
        Array(exclude)
          .map { |name| canonical_workaround_name(name) }
          .reject(&:empty?)
          .to_h { |name| [name, true] }

      Array(model_entry&.workarounds).filter_map do |name|
        canonical = canonical_workaround_name(name)
        next if canonical.empty?
        next if excluded.key?(canonical)

        preset_for(canonical)
      end
    end

    def preset_for(name)
      case canonical_workaround_name(name)
      when "prompt_only"
        TavernKit::VibeTavern::Directives::Presets.directives(modes: [:prompt_only])
      when "json_object_first", "no_json_schema"
        TavernKit::VibeTavern::Directives::Presets.directives(modes: %i[json_object prompt_only])
      when "no_prompt_only"
        TavernKit::VibeTavern::Directives::Presets.directives(modes: %i[json_schema json_object])
      else
        {}
      end
    end

    def canonical_workaround_name(name)
      name.to_s.strip.downcase.tr("-", "_")
    end
  end

  module Util
    module_function

    def safe_filename(str)
      str.to_s.gsub(%r{[^a-zA-Z0-9_.-]+}, "__")
    end

    def deep_symbolize_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(k, v), out|
          key = k.is_a?(Symbol) ? k : k.to_s.to_sym
          out[key] = deep_symbolize_keys(v) unless out.key?(key)
        end
      when Array
        value.map { |v| deep_symbolize_keys(v) }
      else
        value
      end
    end

    def deep_merge_hashes(left, right)
      out = (left.is_a?(Hash) ? left : {}).dup
      (right.is_a?(Hash) ? right : {}).each do |k, v|
        if out[k].is_a?(Hash) && v.is_a?(Hash)
          out[k] = deep_merge_hashes(out[k], v)
        else
          out[k] = v
        end
      end
      out
    end

    def percentile(sorted, p)
      return 0 if sorted.empty?

      idx = (sorted.length * p).floor
      sorted[[idx, sorted.length - 1].min].to_i
    end

    def error_category(message)
      msg = message.to_s
      return "ASSERTION_FAILED" if msg.start_with?("ASSERTION_FAILED:")
      return "DIRECTIVES_RUN_FAILED" if msg.start_with?("DIRECTIVES_RUN_FAILED")
      return "HTTP_ERROR" if msg.start_with?("HTTP_ERROR:")

      msg.strip.empty? ? "" : "UNKNOWN"
    end
  end
end

api_key = ENV["OPENROUTER_API_KEY"].to_s
if api_key.empty?
  warn "Missing OPENROUTER_API_KEY (this script is for live eval via OpenRouter)."
  exit 2
end

base_url = ENV.fetch("OPENROUTER_BASE_URL", "https://openrouter.ai/api")
api_prefix = ENV.fetch("OPENROUTER_API_PREFIX", "/v1")

trials_per_model =
  begin
    Integer(ENV.fetch("OPENROUTER_TRIALS", "1"))
  rescue ArgumentError
    1
  end
trials_per_model = 1 if trials_per_model < 1

parallel_jobs =
  begin
    Integer(ENV.fetch("OPENROUTER_JOBS", "1"))
  rescue ArgumentError, TypeError
    1
  end
parallel_jobs = 1 if parallel_jobs < 1

client_timeout =
  begin
    Float(ENV.fetch("OPENROUTER_CLIENT_TIMEOUT", "60"))
  rescue ArgumentError, TypeError
    60.0
  end
client_timeout = nil if client_timeout <= 0

headers = {}
headers["HTTP-Referer"] = ENV["OPENROUTER_HTTP_REFERER"] if ENV["OPENROUTER_HTTP_REFERER"]
headers["X-Title"] = ENV["OPENROUTER_X_TITLE"] if ENV["OPENROUTER_X_TITLE"]

llm_options_defaults_overrides = {}
if (raw = ENV.fetch("OPENROUTER_LLM_OPTIONS_DEFAULTS_JSON", "").to_s.strip).length.positive?
  begin
    parsed = JSON.parse(raw)
    llm_options_defaults_overrides.merge!(parsed) if parsed.is_a?(Hash)
  rescue JSON::ParserError
    warn "Invalid OPENROUTER_LLM_OPTIONS_DEFAULTS_JSON (must be a JSON object). Ignoring."
  end
end

# Keep temperature unset by default (avoid optimizing eval by changing tone/variance).
# Optional override: OPENROUTER_TEMPERATURE=...
if (raw = ENV.fetch("OPENROUTER_TEMPERATURE", "").to_s.strip).length.positive?
  begin
    llm_options_defaults_overrides[:temperature] = Float(raw)
  rescue ArgumentError, TypeError
    nil
  end
end

if (raw = ENV.fetch("OPENROUTER_TOP_P", "").to_s.strip).length.positive?
  begin
    llm_options_defaults_overrides[:top_p] = Float(raw)
  rescue ArgumentError, TypeError
    nil
  end
end

if (raw = ENV.fetch("OPENROUTER_TOP_K", "").to_s.strip).length.positive?
  begin
    llm_options_defaults_overrides[:top_k] = Integer(raw)
  rescue ArgumentError, TypeError
    nil
  end
end

if (raw = ENV.fetch("OPENROUTER_MIN_P", "").to_s.strip).length.positive?
  begin
    llm_options_defaults_overrides[:min_p] = Float(raw)
  rescue ArgumentError, TypeError
    nil
  end
end

llm_options_defaults_overrides = DirectivesEval::Util.deep_symbolize_keys(llm_options_defaults_overrides)

directives_request_overrides = {}
directives_request_overrides[:max_tokens] =
  begin
    Integer(ENV.fetch("OPENROUTER_MAX_TOKENS", "600"))
  rescue ArgumentError, TypeError
    600
  end

require_parameters_default = ENV.fetch("OPENROUTER_REQUIRE_PARAMETERS", "1") == "1"

provider_directives_preset =
  TavernKit::VibeTavern::Directives::Presets.provider_defaults(
    "openrouter",
    require_parameters: require_parameters_default,
  )

MODEL_CATALOG =
  DirectivesEval::ModelCatalog.build do
    # Keep this list in sync with script/llm_tool_call_eval.rb (model IDs + tags).
    model "deepseek/deepseek-v3.2:nitro", tags: %w[deepseek ds]
    model "deepseek/deepseek-chat-v3-0324:nitro", tags: %w[deepseek ds chat]
    model "x-ai/grok-4.1-fast", tags: %w[x_ai grok]
    model "google/gemini-2.5-flash:nitro", tags: %w[google gemini stable]
    model "google/gemini-3-flash-preview:nitro", tags: %w[google gemini]
    model "google/gemini-3-pro-preview:nitro", tags: %w[google gemini]
    model "anthropic/claude-opus-4.6:nitro", workarounds: [:json_object_first], tags: %w[anthropic claude stable]
    model "openai/gpt-5.2-chat:nitro", workarounds: [:prompt_only], tags: %w[openai gpt]
    model "openai/gpt-5.2:nitro", workarounds: [:prompt_only], tags: %w[openai gpt stable]
    model "minimax/minimax-m2-her", workarounds: [:prompt_only], tags: %w[minimax]
    model "minimax/minimax-m2.1:nitro", workarounds: [:prompt_only], tags: %w[minimax]
    model "qwen/qwen3-30b-a3b-instruct-2507:nitro", tags: %w[qwen stable]
    model "qwen/qwen3-next-80b-a3b-instruct:nitro", tags: %w[qwen stable]
    model "qwen/qwen3-235b-a22b-2507:nitro", tags: %w[qwen stable]
    model "z-ai/glm-4.7:nitro", tags: %w[z_ai glm]
    model "z-ai/glm-4.7-flash:nitro", tags: %w[z_ai glm]
    model "moonshotai/kimi-k2.5:nitro", tags: %w[moonshot kimi]
  end

model_filter = ENV.fetch("OPENROUTER_MODEL_FILTER", "stable")
selected_models = MODEL_CATALOG.filter(model_filter)

if selected_models.empty?
  warn "No models matched OPENROUTER_MODEL_FILTER=#{model_filter.inspect}."
  warn "Available model ids: #{MODEL_CATALOG.ids.join(", ")}"
  exit 2
end

sampling_profile_filter =
  ENV.fetch("OPENROUTER_SAMPLING_PROFILE_FILTER", OpenRouterSamplingProfiles::DEFAULT_PROFILE_ID)
enforce_sampling_profile_applicability =
  ENV.fetch("OPENROUTER_SAMPLING_PROFILE_ENFORCE_APPLICABILITY", "1") == "1"

semantic_repair = ENV.fetch("OPENROUTER_SEMANTIC_REPAIR", "0") == "1"

selected_sampling_profiles = OpenRouterSamplingProfiles::CATALOG.filter(sampling_profile_filter)
default_sampling_profile = OpenRouterSamplingProfiles::CATALOG.find(OpenRouterSamplingProfiles::DEFAULT_PROFILE_ID)
default_sampling_profile ||= OpenRouterSamplingProfiles::Entry.new(id: OpenRouterSamplingProfiles::DEFAULT_PROFILE_ID, llm_options_defaults: {})

if selected_sampling_profiles.empty?
  warn(
    "No sampling profiles matched OPENROUTER_SAMPLING_PROFILE_FILTER=#{sampling_profile_filter.inspect}. " \
    "Falling back to #{default_sampling_profile.id.inspect}.",
  )
  selected_sampling_profiles = [default_sampling_profile]
end

SCENARIOS = [
  {
    id: "show_form",
    system: "You are a UI-driving assistant. Use directives to drive UI.",
    user: "Create a new character. Show the new-character form.",
    assert: lambda do |result|
      dirs = Array(result[:directives])
      dirs.any? { |d| d.is_a?(Hash) && d["type"] == "ui.show_form" } ? [] : ["missing ui.show_form"]
    end,
  },
  {
    id: "toast",
    system: "You are a UI-driving assistant. Use directives to drive UI.",
    user: "Tell the user we saved the draft successfully.",
    assert: lambda do |result|
      dirs = Array(result[:directives])
      dirs.any? { |d| d.is_a?(Hash) && d["type"] == "ui.toast" } ? [] : ["missing ui.toast"]
    end,
  },
  {
    id: "patch_draft",
    system: "You are a UI-driving assistant. Use directives to drive UI.",
    user: "Set the draft field /draft/foo to value \"bar\".",
    assert: lambda do |result|
      dirs = Array(result[:directives])
      patch = dirs.find { |d| d.is_a?(Hash) && d["type"] == "ui.patch" }
      return ["missing ui.patch"] unless patch

      ops = patch.fetch("payload", {}).fetch("ops", nil)
      ok = ops.is_a?(Array) && ops.any? { |op| op.is_a?(Hash) && op["op"] == "set" && op["path"] == "/draft/foo" && op.key?("value") }
      ok ? [] : ["missing set op for /draft/foo"]
    end,
  },
  {
    id: "request_upload",
    system: "You are a UI-driving assistant. Use directives to drive UI.",
    user: "Ask the user to upload a character image.",
    assert: lambda do |result|
      dirs = Array(result[:directives])
      dirs.any? { |d| d.is_a?(Hash) && d["type"] == "ui.request_upload" } ? [] : ["missing ui.request_upload"]
    end,
  },
].freeze

default_scenario_ids = %w[show_form toast patch_draft request_upload]
simple_scenario_ids = %w[show_form toast]
typical_scenario_ids = default_scenario_ids
extreme_scenario_ids = %w[patch_draft request_upload]

raw_requested_scenarios = ENV.fetch("OPENROUTER_SCENARIOS", "").to_s
requested_scenario_tokens =
  raw_requested_scenarios
    .split(",")
    .map(&:strip)
    .reject(&:empty?)

requested_scenarios =
  if requested_scenario_tokens.any? { |v| %w[all full *].include?(v.downcase) }
    nil
  elsif requested_scenario_tokens.empty?
    default_scenario_ids
  else
    expanded =
      requested_scenario_tokens.flat_map do |tok|
        case tok.downcase
        when "default", "smoke"
          default_scenario_ids
        when "simple"
          simple_scenario_ids
        when "typical"
          typical_scenario_ids
        when "extreme"
          extreme_scenario_ids
        else
          tok
        end
      end

    expanded.map(&:to_s).map(&:strip).reject(&:empty?).uniq
  end

scenarios =
  if requested_scenarios
    SCENARIOS.select { |s| requested_scenarios.include?(s[:id]) }
  else
    SCENARIOS
  end

if scenarios.empty?
  warn(
    "No scenarios selected from OPENROUTER_SCENARIOS=#{raw_requested_scenarios.inspect}. " \
    "Falling back to default: #{default_scenario_ids.join(", ")}",
  )
  scenarios = SCENARIOS.select { |s| default_scenario_ids.include?(s[:id]) }
end

if scenarios.empty?
  warn "No scenarios selected. Available: #{SCENARIOS.map { |s| s[:id] }.join(", ")}"
  exit 2
end

timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
out_dir = Rails.root.join("tmp", "llm_directives_eval_reports", timestamp)
FileUtils.mkdir_p(out_dir)

log_mutex = Mutex.new
log_line =
  lambda do |line|
    log_mutex.synchronize do
      $stderr.puts(line)
      $stderr.flush
    end
  end

run_task =
  lambda do |task, task_index, task_total|
    model_entry = task.fetch(:model_entry)
    model_index = task.fetch(:model_index)
    sampling_profile = task.fetch(:sampling_profile)

    model = model_entry.id
    sampling_profile_id = sampling_profile.id
    model_workaround_presets = DirectivesEval::ModelWorkarounds.presets_for(model_entry)

    directives_preset =
      TavernKit::VibeTavern::Directives::Presets.merge(
        TavernKit::VibeTavern::Directives::Presets.default_directives,
        provider_directives_preset,
        TavernKit::VibeTavern::Directives::Presets.directives(
          request_overrides: directives_request_overrides,
        ),
        *model_workaround_presets,
      )

    llm_options_defaults =
      DirectivesEval::Util.deep_merge_hashes(
        sampling_profile.llm_options_defaults,
        llm_options_defaults_overrides,
      )

    client =
      SimpleInference::Client.new(
        base_url: base_url,
        api_prefix: api_prefix,
        api_key: api_key,
        headers: headers,
        timeout: client_timeout,
      )

    directives_runner =
      TavernKit::VibeTavern::Directives::Runner.build(
        client: client,
        model: model,
        llm_options_defaults: llm_options_defaults,
        preset: directives_preset,
      )

    directives_registry =
      TavernKit::VibeTavern::Directives::Registry.new(
        definitions: [
          {
            type: "ui.show_form",
            description: "payload: {form_id:String}",
            aliases: %w[show_form showform ui_show_form],
          },
          {
            type: "ui.toast",
            description: "payload: {message:String, level?:info|success|warning|error}",
            aliases: %w[toast ui_toast],
          },
          {
            type: "ui.patch",
            description:
              "payload: {ops:Array<{op,path,value?,index?}>}; op: set|delete|append|insert (also accepts add/replace/remove/push); path prefixes: /draft/ /ui_state/",
            aliases: %w[patch set_draft set_state patch_draft patch_state ui_patch],
          },
          {
            type: "ui.request_upload",
            description: "payload: {purpose:String, accept?:[String], max_bytes?:Integer}",
            aliases: %w[request_upload requestupload upload ui_request_upload],
          },
        ],
      )

    payload_validator =
      lambda do |type, payload|
        case type.to_s
        when "ui.show_form"
          { code: "MISSING_FORM_ID" } if payload.fetch("form_id", "").to_s.strip.empty?
        when "ui.toast"
          { code: "MISSING_MESSAGE" } if payload.fetch("message", "").to_s.strip.empty?
        when "ui.patch"
          # Tolerate both payload shapes:
          # - { "ops": [...] } (preferred)
          # - { "op": "...", "path": "...", "value": ... } (single op at root)
          ops = payload.key?("ops") ? payload.fetch("ops", nil) : payload
          normalized = TavernKit::VibeTavern::Directives::Validator.normalize_patch_ops(ops)
          return normalized unless normalized[:ok]

          payload["ops"] = normalized[:ops]
          nil
        when "ui.request_upload"
          { code: "MISSING_PURPOSE" } if payload.fetch("purpose", "").to_s.strip.empty?
        end
      end

    structured_output_options = {
      registry: directives_registry,
      allowed_types: directives_registry.types,
      type_aliases: directives_registry.type_aliases,
      output_instructions: directives_registry.instructions_text,
      payload_validator: payload_validator,
    }

    runs = []
    failures = []

    trials_per_model.times do |trial_idx|
      scenarios.each do |scenario|
        scenario_id = scenario[:id]
        task_idx = task_index + 1
        model_idx = model_index + 1

        log_line.call(
          "[#{task_idx}/#{task_total}] [#{model_idx}/#{selected_models.length}] testing #{model} profile=#{sampling_profile_id} scenario=#{scenario_id} (trial #{trial_idx + 1}/#{trials_per_model})...",
        )

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        ok = true
        error = nil
        result = nil

        begin
          result =
            directives_runner.run(
              system: scenario[:system],
              history: [TavernKit::Prompt::Message.new(role: :user, content: scenario[:user])],
              structured_output_options: structured_output_options,
              result_validator: semantic_repair ? scenario[:assert] : nil,
            )

          if result[:ok] == true
            reasons = Array(scenario[:assert].call(result))
            unless reasons.empty?
              ok = false
              error = "ASSERTION_FAILED: #{reasons.join("; ")}"
            end
          else
            ok = false
            attempts = Array(result[:attempts])
            last_attempt = attempts.last
            last_semantic =
              attempts.reverse.find { |a| a.is_a?(Hash) && a[:semantic_error].is_a?(Hash) }
            if last_attempt.is_a?(Hash) && last_attempt[:http_error]
              status = last_attempt[:http_status]
              msg = last_attempt[:message].to_s
              error = "DIRECTIVES_RUN_FAILED: HTTP #{status} #{msg}".strip
            elsif last_semantic
              reasons = Array(last_semantic.dig(:semantic_error, :reasons)).map(&:to_s).map(&:strip).reject(&:empty?)
              error = "ASSERTION_FAILED: #{reasons.join("; ")}" if reasons.any?
              error ||= "ASSERTION_FAILED"
            else
              error = "DIRECTIVES_RUN_FAILED"
            end
          end
        rescue SimpleInference::Errors::HTTPError => e
          ok = false
          error = "HTTP_ERROR: #{e.status} #{e.message}"
        rescue StandardError => e
          ok = false
          error = "#{e.class}: #{e.message}"
        end

        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

        report = {
          model: model,
          sampling_profile: sampling_profile_id,
          llm_options_defaults: llm_options_defaults,
          scenario: scenario_id,
          trial: trial_idx + 1,
          ok: ok,
          elapsed_ms: elapsed_ms,
          mode: result.is_a?(Hash) ? result[:mode] : nil,
          assistant_text: result.is_a?(Hash) ? result[:assistant_text] : nil,
          directives: result.is_a?(Hash) ? result[:directives] : nil,
          warnings: result.is_a?(Hash) ? result[:warnings] : nil,
          attempts: result.is_a?(Hash) ? result[:attempts] : nil,
          error: error,
        }

        safe_model = DirectivesEval::Util.safe_filename(model)
        safe_profile = DirectivesEval::Util.safe_filename(sampling_profile_id)
        safe_scenario = DirectivesEval::Util.safe_filename(scenario_id)
        file_name = "#{safe_model}__#{safe_profile}__#{safe_scenario}__trial_#{format("%02d", trial_idx + 1)}.json"
        File.write(out_dir.join(file_name), JSON.pretty_generate(report))

        run_meta = {
          model: model,
          sampling_profile: sampling_profile_id,
          scenario: scenario_id,
          trial: trial_idx + 1,
          ok: ok,
          elapsed_ms: elapsed_ms,
          mode: report[:mode],
          error: error,
          report: file_name,
        }

        runs << run_meta
        failures << run_meta unless ok

        status_str = ok ? "OK" : "FAIL"
        log_line.call(
          "[#{task_idx}/#{task_total}] #{status_str} #{model} profile=#{sampling_profile_id} scenario=#{scenario_id} (trial #{trial_idx + 1}, #{elapsed_ms}ms)",
        )
      end
    end

    ok_count = runs.count { |t| t[:ok] }
    rate = ok_count.fdiv(runs.size)
    elapsed = runs.map { |t| t[:elapsed_ms].to_i }.sort

    {
      model: model,
      sampling_profile: sampling_profile_id,
      runs: runs.size,
      ok: ok_count,
      ok_rate: rate,
      ms_p50: DirectivesEval::Util.percentile(elapsed, 0.50),
      ms_p95: DirectivesEval::Util.percentile(elapsed, 0.95),
      run_results: runs,
      failure_samples: failures.first(3),
    }
  end

task_list =
  selected_models.each_with_index.flat_map do |model_entry, model_index|
    profiles =
      if enforce_sampling_profile_applicability
        selected_sampling_profiles.select { |p| p.applies_to_model?(model_entry.id) }
      else
        selected_sampling_profiles
      end

    profiles = [default_sampling_profile] if profiles.empty?

    profiles.map do |profile|
      {
        model_entry: model_entry,
        model_index: model_index,
        sampling_profile: profile,
      }
    end
  end

parallel_jobs = [parallel_jobs, task_list.length].min

if parallel_jobs == 1
  reports = task_list.each_with_index.map { |task, ti| run_task.call(task, ti, task_list.length) }
else
  queue = Queue.new
  task_list.each_with_index { |item, ti| queue << [item, ti] }

  reports_by_index = Array.new(task_list.length)
  workers =
    Array.new(parallel_jobs) do
      Thread.new do
        loop do
          item, task_index =
            begin
              queue.pop(true)
            rescue ThreadError
              break
            end
          reports_by_index[task_index] = run_task.call(item, task_index, task_list.length)
        end
      end
    end

  workers.each(&:join)
  reports = reports_by_index.compact
end

summary = {
  ts: Time.now.utc.iso8601,
  base_url: base_url,
  api_prefix: api_prefix,
  require_parameters: require_parameters_default,
  sampling_profile_filter: sampling_profile_filter,
  sampling_profiles: selected_sampling_profiles.map(&:id),
  sampling_profile_enforce_applicability: enforce_sampling_profile_applicability,
  semantic_repair: semantic_repair,
  llm_options_defaults_overrides: llm_options_defaults_overrides,
  trials_per_model: trials_per_model,
  jobs: parallel_jobs,
  scenarios: scenarios.map { |s| s[:id] },
  models: reports,
  output_dir: out_dir.to_s,
}
File.write(out_dir.join("summary.json"), JSON.pretty_generate(summary))

all_runs = reports.flat_map { |r| Array(r[:run_results]) }
summary_by_scenario =
  all_runs.each_with_object({}) do |run, out|
    sid = run[:scenario].to_s
    out[sid] ||= { "runs" => 0, "ok" => 0, "errors" => Hash.new(0) }
    out[sid]["runs"] += 1
    out[sid]["ok"] += 1 if run[:ok] == true

    unless run[:ok] == true
      cat = DirectivesEval::Util.error_category(run[:error])
      cat = "unknown" if cat.empty?
      out[sid]["errors"][cat] += 1
    end
  end
summary_by_scenario.each_value { |v| v["errors"] = v["errors"].to_h }
File.write(out_dir.join("summary_by_scenario.json"), JSON.pretty_generate(summary_by_scenario))

puts "LLM Directives Eval"
puts "ts: #{summary[:ts]}"
puts "models: #{reports.size}"
puts "scenarios: #{summary[:scenarios].join(",")}"
puts "trials_per_model: #{trials_per_model}"
puts "jobs: #{parallel_jobs}"
puts "require_parameters: #{require_parameters_default}"
puts "sampling_profile_filter: #{sampling_profile_filter}"
puts "sampling_profiles: #{selected_sampling_profiles.map(&:id).join(",")}"
puts "full report: #{out_dir.relative_path_from(Rails.root)}"
puts

header = ["model", "profile", "runs", "ok", "rate", "p50_ms", "p95_ms", "sample"]
rows =
  reports.map do |r|
    sample = Array(r[:failure_samples]).first
    sample_path = sample ? sample[:report].to_s : "-"
    [
      r[:model].to_s,
      r[:sampling_profile].to_s,
      r[:runs].to_s,
      r[:ok].to_s,
      format("%.0f%%", r[:ok_rate].to_f * 100),
      r[:ms_p50].to_s,
      r[:ms_p95].to_s,
      sample_path,
    ]
  end

widths = header.map.with_index { |h, idx| ([h.length] + rows.map { |row| row[idx].length }).max }
fmt = widths.map { |w| "%-#{w}s" }.join(" | ")
sep = widths.map { |w| "-" * w }.join("-|-")

puts format(fmt, *header)
puts sep
rows.each { |row| puts format(fmt, *row) }
