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
      return "EMPTY_ASSISTANT_TEXT" if msg.start_with?("EMPTY_ASSISTANT_TEXT")
      return "CONNECTION_ERROR" if msg.start_with?("CONNECTION_ERROR:")
      return "TIMEOUT_ERROR" if msg.start_with?("TIMEOUT_ERROR:")
      return "DECODE_ERROR" if msg.start_with?("DECODE_ERROR:")
      return "ASSERTION_FAILED" if msg.start_with?("ASSERTION_FAILED:")
      return "LANGUAGE_DRIFT" if msg.start_with?("LANGUAGE_DRIFT:")
      return "DIRECTIVES_RUN_FAILED" if msg.start_with?("DIRECTIVES_RUN_FAILED")
      return "HTTP_ERROR" if msg.start_with?("HTTP_ERROR:")
      return "TIMEOUT" if msg.downcase.include?("timeout")

      msg.strip.empty? ? "" : "UNKNOWN"
    end

    def attempts_count(attempts)
      Array(attempts).length
    end

    def attempts_include_http_404?(attempts)
      Array(attempts).any? do |attempt|
        next false unless attempt.is_a?(Hash)

        next false unless attempt[:http_error] == true

        attempt.fetch(:http_status, nil).to_i == 404
      end
    end

    def attempts_include_semantic_error?(attempts)
      Array(attempts).any? do |attempt|
        next false unless attempt.is_a?(Hash)

        attempt[:semantic_error].is_a?(Hash)
      end
    end
  end

  module Strategies
    Entry = Struct.new(
      :id,
      :semantic_repair,
      :apply_provider_defaults,
      :apply_model_workarounds,
      :repair_retry_count,
      :tags,
      keyword_init: true,
    ) do
      def initialize(
        id:,
        semantic_repair:,
        apply_provider_defaults:,
        apply_model_workarounds:,
        repair_retry_count: nil,
        tags: []
      )
        super(
          id: id.to_s,
          semantic_repair: semantic_repair == true,
          apply_provider_defaults: apply_provider_defaults == true,
          apply_model_workarounds: apply_model_workarounds == true,
          repair_retry_count: repair_retry_count,
          tags: normalize_tags(tags),
        )
      end

      def matches?(raw_token)
        token = raw_token.to_s.strip.downcase
        return false if token.empty?

        candidates = ([id] + tags).map(&:to_s).map(&:downcase).uniq

        if token.include?("*")
          candidates.any? { |value| File.fnmatch(token, value) }
        else
          candidates.include?(token)
        end
      end

      private

      def normalize_tags(value)
        Array(value).map { |item| item.to_s.strip.downcase }.reject(&:empty?).uniq
      end
    end

    RAW =
      Entry.new(
        id: "raw",
        semantic_repair: false,
        apply_provider_defaults: false,
        apply_model_workarounds: false,
        repair_retry_count: 0,
        tags: %w[raw naked unoptimized],
      ).freeze

    BASELINE =
      Entry.new(
        id: "baseline",
        semantic_repair: false,
        apply_provider_defaults: true,
        apply_model_workarounds: true,
        tags: %w[default off semantic_repair_off],
      ).freeze

    PRODUCTION =
      Entry.new(
        id: "production",
        semantic_repair: true,
        apply_provider_defaults: true,
        apply_model_workarounds: true,
        tags: %w[prod on semantic_repair_on],
      ).freeze

    MATRIX_CATALOG = [BASELINE, PRODUCTION].freeze
    ALL = [RAW, BASELINE, PRODUCTION].freeze

    module_function

    def filter(raw_filter, fallback_semantic_repair:)
      tokens = raw_filter.to_s.split(",").map(&:strip).reject(&:empty?)
      return [fallback_semantic_repair == true ? PRODUCTION : BASELINE] if tokens.empty?

      return ALL.dup if tokens.any? { |token| %w[all full *].include?(token.downcase) }

      include_tokens = tokens.reject { |token| token.start_with?("!") }
      exclude_tokens = tokens.select { |token| token.start_with?("!") }.map { |t| t.delete_prefix("!") }.reject(&:empty?)

      selected =
        if include_tokens.empty?
          ALL
        else
          ALL.select { |entry| include_tokens.any? { |token| entry.matches?(token) } }
        end

      selected.reject { |entry| exclude_tokens.any? { |token| entry.matches?(token) } }
    end
  end

  module LanguagePolicy
    Entry = Struct.new(:id, :enabled, :target_lang, :tags, keyword_init: true) do
      def initialize(id:, enabled:, target_lang: nil, tags: [])
        super(
          id: id.to_s,
          enabled: enabled == true,
          target_lang: target_lang&.to_s,
          tags: normalize_tags(tags),
        )
      end

      def matches?(raw_token)
        token = raw_token.to_s.strip.downcase
        return false if token.empty?

        candidates = ([id] + tags).map(&:to_s).map(&:downcase).uniq

        if token.include?("*")
          candidates.any? { |value| File.fnmatch(token, value) }
        else
          candidates.include?(token)
        end
      end

      private

      def normalize_tags(value)
        Array(value).map { |item| item.to_s.strip.downcase }.reject(&:empty?).uniq
      end
    end

    DEFAULT_TARGET_LANGS = %w[zh-CN ja-JP].freeze

    OFF =
      Entry.new(
        id: "off",
        enabled: false,
        tags: %w[off disabled none 0 false],
      ).freeze

    CANONICAL_TARGET_LANGS = {
      "en" => "en-US",
      "en-us" => "en-US",
      "zh-cn" => "zh-CN",
      "zh-tw" => "zh-TW",
      "zh-hans" => "zh-CN",
      "zh-hans-cn" => "zh-CN",
      "zh-hant" => "zh-TW",
      "zh-hant-tw" => "zh-TW",
      "ko-kr" => "ko-KR",
      "ko" => "ko-KR",
      "ja-jp" => "ja-JP",
      "ja" => "ja-JP",
      "yue-hk" => "yue-HK",
      "yue" => "yue-HK",
    }.freeze

    module_function

    def canonical_target_lang(raw)
      s = raw.to_s.strip.tr("_", "-")
      return "" if s.empty?

      CANONICAL_TARGET_LANGS.fetch(s.downcase, s)
    end

    def filter(raw_filter, matrix: false)
      return matrix_entries(DEFAULT_TARGET_LANGS) if matrix

      tokens = raw_filter.to_s.split(",").map(&:strip).reject(&:empty?)
      return [OFF] if tokens.empty?
      return matrix_entries(DEFAULT_TARGET_LANGS) if tokens.any? { |token| %w[all full *].include?(token.downcase) }

      include_tokens = tokens.reject { |token| token.start_with?("!") }
      exclude_tokens = tokens.select { |token| token.start_with?("!") }.map { |t| t.delete_prefix("!") }.reject(&:empty?)

      selected =
        if include_tokens.empty?
          tokens
        else
          include_tokens
        end

      entries =
        selected.flat_map do |token|
          case token.to_s.strip.downcase
          when "off", "disabled", "none", "0", "false"
            OFF
          when "on", "enabled", "1", "true"
            matrix_entries(DEFAULT_TARGET_LANGS)
          else
            canonical = canonical_target_lang(token)
            canonical.empty? ? nil : entry_for(canonical)
          end
        end

      entries = Array(entries).flatten.compact.uniq { |e| e.id }
      entries = [OFF] if entries.empty?

      entries.reject { |entry| exclude_tokens.any? { |token| entry.matches?(token) } }
    end

    def language_shape(text, target_lang:)
      t = strip_language_spans(text)
      return "unknown" if t.strip.empty?

      lang = canonical_target_lang(target_lang)
      return "unknown" if lang.empty?

      has_kana = t.match?(/[\u3040-\u30FF]/)
      has_han = t.match?(/\p{Han}/)
      has_hangul = t.match?(/[\uAC00-\uD7AF]/)
      has_latin = t.match?(/[A-Za-z]/)

      case lang
      when "ja-JP"
        return "ok" if has_kana
        return "unknown" if has_han
        return "drift" if has_hangul
        return "unknown" if has_latin

        "unknown"
      when "zh-CN", "zh-TW", "yue-HK"
        return "drift" if has_kana
        return "ok" if has_han
        return "drift" if has_hangul
        return "unknown" if has_latin

        "unknown"
      when "ko-KR"
        return "ok" if has_hangul
        return "unknown" if has_han
        return "drift" if has_kana
        return "unknown" if has_latin

        "unknown"
      when "en-US"
        return "ok" if has_latin
        return "unknown" if has_han || has_kana || has_hangul

        "unknown"
      else
        "unknown"
      end
    rescue StandardError
      "unknown"
    end

    def strip_language_spans(text)
      text.to_s.gsub(/<lang\b[^>]*>.*?<\/lang>/im, "")
    rescue StandardError
      text.to_s
    end

    def entry_for(target_lang)
      canonical = canonical_target_lang(target_lang)
      Entry.new(id: canonical, enabled: true, target_lang: canonical, tags: [canonical.downcase])
    end
    private_class_method :entry_for

    def matrix_entries(langs)
      [OFF] + Array(langs).map { |lang| entry_for(lang) }
    end
    private_class_method :matrix_entries
  end
end

env_blank =
  lambda do |key|
    !ENV.key?(key) || ENV.fetch(key, "").to_s.strip.empty?
  end

eval_preset = ENV.fetch("OPENROUTER_EVAL_PRESET", "").to_s.strip.downcase
eval_preset = "full" if eval_preset.empty? && ENV.fetch("OPENROUTER_FULL", "0") == "1"

if %w[full all].include?(eval_preset)
  ENV["OPENROUTER_JOBS"] = "2" if env_blank.call("OPENROUTER_JOBS")
  ENV["OPENROUTER_TRIALS"] = "10" if env_blank.call("OPENROUTER_TRIALS")
  ENV["OPENROUTER_MODEL_FILTER"] = "all" if env_blank.call("OPENROUTER_MODEL_FILTER")
  ENV["OPENROUTER_SAMPLING_PROFILE_FILTER"] = "default,recommended,conversation,creative,tool_calling" if env_blank.call("OPENROUTER_SAMPLING_PROFILE_FILTER")
  ENV["OPENROUTER_SCENARIOS"] = "all" if env_blank.call("OPENROUTER_SCENARIOS")

  # Full preset includes the raw control group + baseline + production.
  ENV["OPENROUTER_STRATEGY_FILTER"] = "raw,baseline,production" if env_blank.call("OPENROUTER_STRATEGY_FILTER")

  # Keep matrix off: it would override the filter and drop the raw control group.
  ENV["OPENROUTER_STRATEGY_MATRIX"] = "0"
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

empty_response_retry_count =
  begin
    Integer(ENV.fetch("OPENROUTER_EMPTY_RESPONSE_RETRY_COUNT", "1"))
  rescue ArgumentError, TypeError
    1
  end
empty_response_retry_count = 0 if empty_response_retry_count < 0

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

strategy_matrix = ENV.fetch("OPENROUTER_STRATEGY_MATRIX", "0") == "1"
raw_strategy_filter = ENV.fetch("OPENROUTER_STRATEGY_FILTER", "").to_s.strip
fallback_semantic_repair = ENV.fetch("OPENROUTER_SEMANTIC_REPAIR", "0") == "1"

requested_strategies =
  if strategy_matrix
    DirectivesEval::Strategies::MATRIX_CATALOG.dup
  else
    DirectivesEval::Strategies.filter(
      raw_strategy_filter,
      fallback_semantic_repair: fallback_semantic_repair,
    )
  end

if requested_strategies.empty?
  warn(
    "No strategies selected from OPENROUTER_STRATEGY_FILTER=#{raw_strategy_filter.inspect}. " \
    "Falling back to #{DirectivesEval::Strategies::BASELINE.id.inspect}.",
  )
  requested_strategies = [DirectivesEval::Strategies::BASELINE]
end

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

language_policy_matrix = ENV.fetch("OPENROUTER_LANGUAGE_POLICY_MATRIX", "0") == "1"
raw_language_policy_filter = ENV.fetch("OPENROUTER_LANGUAGE_POLICY_FILTER", "").to_s
language_policy_strict = ENV.fetch("OPENROUTER_LANGUAGE_POLICY_STRICT", "0") == "1"

selected_language_policies =
  DirectivesEval::LanguagePolicy.filter(
    raw_language_policy_filter,
    matrix: language_policy_matrix,
  )

if selected_language_policies.empty?
  warn(
    "No language policy entries selected from OPENROUTER_LANGUAGE_POLICY_FILTER=#{raw_language_policy_filter.inspect}. " \
    "Falling back to off.",
  )
  selected_language_policies = [DirectivesEval::LanguagePolicy::OFF]
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
    strategy = task.fetch(:strategy)
    language_policy = task.fetch(:language_policy)

    model = model_entry.id
    sampling_profile_id = sampling_profile.id
    strategy_id = strategy.id.to_s
    language_policy_id = language_policy.id.to_s
    language_policy_enabled = language_policy.enabled == true
    language_policy_target_lang = language_policy.target_lang.to_s
    language_policy_target_lang = nil if language_policy_target_lang.strip.empty?
    semantic_repair = strategy.semantic_repair == true
    apply_provider_defaults = strategy.apply_provider_defaults == true
    apply_model_workarounds = strategy.apply_model_workarounds == true
    repair_retry_count = strategy.repair_retry_count

    model_workaround_presets =
      if apply_model_workarounds
        DirectivesEval::ModelWorkarounds.presets_for(model_entry)
      else
        []
      end

    directives_preset =
      TavernKit::VibeTavern::Directives::Presets.merge(
        TavernKit::VibeTavern::Directives::Presets.default_directives,
        (apply_provider_defaults ? provider_directives_preset : {}),
        TavernKit::VibeTavern::Directives::Presets.directives(
          request_overrides: directives_request_overrides,
        ),
        (repair_retry_count.nil? ? {} : TavernKit::VibeTavern::Directives::Presets.directives(repair_retry_count: repair_retry_count)),
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

    context_inputs = { directives: directives_preset }
    if language_policy_enabled && language_policy_target_lang
      context_inputs[:language_policy] = {
        enabled: true,
        target_lang: language_policy_target_lang,
      }
    end

    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openrouter",
        model: model,
        context: context_inputs,
        llm_options_defaults: llm_options_defaults,
      )

    directives_runner =
      TavernKit::VibeTavern::Directives::Runner.build(
        client: client,
        runner_config: runner_config,
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
          "[#{task_idx}/#{task_total}] [#{model_idx}/#{selected_models.length}] testing #{model} profile=#{sampling_profile_id} strategy=#{strategy_id} lang=#{language_policy_id} scenario=#{scenario_id} (trial #{trial_idx + 1}/#{trials_per_model})...",
        )

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        retry_attempts_used = 0
        max_attempts = empty_response_retry_count + 1

        ok = true
        error = nil
        result = nil
        assistant_text_language_shape = nil
        assistant_text_language_ok = nil

        while retry_attempts_used < max_attempts
          retry_attempts_used += 1

          ok = true
          error = nil
          result = nil

          begin
            result =
              directives_runner.run(
                system: scenario[:system],
                history: [TavernKit::PromptBuilder::Message.new(role: :user, content: scenario[:user])],
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
          rescue SimpleInference::Errors::TimeoutError => e
            ok = false
            error = "TIMEOUT_ERROR: #{DirectivesEval::Util.truncate(e.message, max_chars: 400)}"
          rescue SimpleInference::Errors::ConnectionError => e
            ok = false
            error = "CONNECTION_ERROR: #{DirectivesEval::Util.truncate(e.message, max_chars: 400)}"
          rescue SimpleInference::Errors::DecodeError => e
            ok = false
            error = "DECODE_ERROR: #{DirectivesEval::Util.truncate(e.message, max_chars: 400)}"
          rescue StandardError => e
            ok = false
            error = "#{e.class}: #{e.message}"
          end

          had_http_error =
            result.is_a?(Hash) &&
              Array(result[:attempts]).any? { |a| a.is_a?(Hash) && a[:http_error] == true }

          retryable_empty_response =
            result.is_a?(Hash) &&
              result[:assistant_text].to_s.strip.empty? &&
              Array(result[:directives]).empty? &&
              !had_http_error

          failure_category = DirectivesEval::Util.error_category(error)
          retryable_network_error =
            !had_http_error &&
              %w[CONNECTION_ERROR TIMEOUT_ERROR DECODE_ERROR].include?(failure_category)
          retryable_transient_failure = retryable_empty_response || retryable_network_error

          break unless retryable_transient_failure && retry_attempts_used < max_attempts

          log_line.call(
            "  [#{task_idx}/#{task_total}] [#{model_idx}/#{selected_models.length}] .. transient failure (#{failure_category}); retrying " \
            "(attempt #{retry_attempts_used + 1}/#{max_attempts})",
          )
        end

        assistant_text_value = result.is_a?(Hash) ? result[:assistant_text] : nil
        directives_value = result.is_a?(Hash) ? result[:directives] : nil
        final_empty_response =
          result.is_a?(Hash) &&
            assistant_text_value.to_s.strip.empty? &&
            Array(directives_value).empty? &&
            had_http_error != true

        if final_empty_response
          category = DirectivesEval::Util.error_category(error)
          if category.empty? || category == "ASSERTION_FAILED"
            ok = false
            error = "EMPTY_ASSISTANT_TEXT"
          end
        end

        if language_policy_enabled
          assistant_text_language_shape =
            DirectivesEval::LanguagePolicy.language_shape(
              assistant_text_value,
              target_lang: language_policy_target_lang,
            )

          assistant_text_language_ok =
            case assistant_text_language_shape
            when "ok" then true
            when "drift" then false
            else
              nil
            end

          if ok && language_policy_strict && assistant_text_language_shape == "drift"
            ok = false
            error = "LANGUAGE_DRIFT: expected #{language_policy_target_lang}"
          end
        end

        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

        report = {
          model: model,
          sampling_profile: sampling_profile_id,
          strategy: strategy_id,
          empty_response_retry: {
            max_retries: empty_response_retry_count,
            attempts: retry_attempts_used,
          },
          language_policy: {
            id: language_policy_id,
            enabled: language_policy_enabled,
            target_lang: language_policy_target_lang,
            strict: language_policy_strict,
          },
          semantic_repair: semantic_repair,
          apply_provider_defaults: apply_provider_defaults,
          apply_model_workarounds: apply_model_workarounds,
          repair_retry_count: repair_retry_count,
          llm_options_defaults: llm_options_defaults,
          scenario: scenario_id,
          trial: trial_idx + 1,
          ok: ok,
          elapsed_ms: elapsed_ms,
          mode: result.is_a?(Hash) ? result[:mode] : nil,
          assistant_text: result.is_a?(Hash) ? result[:assistant_text] : nil,
          assistant_text_language_shape: assistant_text_language_shape,
          assistant_text_language_ok: assistant_text_language_ok,
          directives: result.is_a?(Hash) ? result[:directives] : nil,
          warnings: result.is_a?(Hash) ? result[:warnings] : nil,
          attempts: result.is_a?(Hash) ? result[:attempts] : nil,
          error: error,
        }

        safe_model = DirectivesEval::Util.safe_filename(model)
        safe_profile = DirectivesEval::Util.safe_filename(sampling_profile_id)
        safe_strategy = DirectivesEval::Util.safe_filename(strategy_id)
        safe_lang = DirectivesEval::Util.safe_filename(language_policy_id)
        safe_scenario = DirectivesEval::Util.safe_filename(scenario_id)
        file_name = "#{safe_model}__#{safe_profile}__#{safe_strategy}__lang_#{safe_lang}__#{safe_scenario}__trial_#{format("%02d", trial_idx + 1)}.json"
        File.write(out_dir.join(file_name), JSON.pretty_generate(report))

        attempts = report[:attempts]
        attempts_count = DirectivesEval::Util.attempts_count(attempts)
        had_http_404 = DirectivesEval::Util.attempts_include_http_404?(attempts)
        had_semantic_error = DirectivesEval::Util.attempts_include_semantic_error?(attempts)

        run_meta = {
          model: model,
          sampling_profile: sampling_profile_id,
          strategy: strategy_id,
          empty_response_retry_attempts: retry_attempts_used,
          language_policy: language_policy_id,
          scenario: scenario_id,
          trial: trial_idx + 1,
          ok: ok,
          elapsed_ms: elapsed_ms,
          mode: report[:mode],
          assistant_text_language_shape: assistant_text_language_shape,
          assistant_text_language_ok: assistant_text_language_ok,
          attempts_count: attempts_count,
          had_http_404: had_http_404,
          had_semantic_error: had_semantic_error,
          error: error,
          report: file_name,
        }

        runs << run_meta
        failures << run_meta unless ok

        status_str = ok ? "OK" : "FAIL"
        log_line.call(
          "[#{task_idx}/#{task_total}] #{status_str} #{model} profile=#{sampling_profile_id} strategy=#{strategy_id} lang=#{language_policy_id} scenario=#{scenario_id} (trial #{trial_idx + 1}, #{elapsed_ms}ms)",
        )
      end
    end

    ok_count = runs.count { |t| t[:ok] }
    rate = ok_count.fdiv(runs.size)
    elapsed = runs.map { |t| t[:elapsed_ms].to_i }.sort
    multi_attempt_runs = runs.count { |t| t[:attempts_count].to_i > 1 }
    http_404_runs = runs.count { |t| t[:had_http_404] == true }
    semantic_error_runs = runs.count { |t| t[:had_semantic_error] == true }
    modes =
      runs.each_with_object(Hash.new(0)) do |t, out|
        mode = t[:mode].to_s
        next if mode.empty?

        out[mode] += 1
      end

    lang_ok_runs = nil
    lang_drift_runs = nil
    lang_unknown_runs = nil
    if language_policy_enabled
      lang_ok_runs = runs.count { |t| t[:assistant_text_language_ok] == true }
      lang_drift_runs = runs.count { |t| t[:assistant_text_language_shape].to_s == "drift" }
      lang_unknown_runs = runs.count { |t| t[:assistant_text_language_shape].to_s == "unknown" }
    end

    {
      model: model,
      sampling_profile: sampling_profile_id,
      strategy: strategy_id,
      language_policy: language_policy_id,
      language_enabled: language_policy_enabled,
      runs: runs.size,
      ok: ok_count,
      ok_rate: rate,
      language_ok_runs: lang_ok_runs,
      language_ok_rate: lang_ok_runs ? lang_ok_runs.fdiv(runs.size) : nil,
      language_drift_runs: lang_drift_runs,
      language_drift_rate: lang_drift_runs ? lang_drift_runs.fdiv(runs.size) : nil,
      language_unknown_runs: lang_unknown_runs,
      language_unknown_rate: lang_unknown_runs ? lang_unknown_runs.fdiv(runs.size) : nil,
      multi_attempt_runs: multi_attempt_runs,
      multi_attempt_rate: multi_attempt_runs.fdiv(runs.size),
      http_404_runs: http_404_runs,
      http_404_rate: http_404_runs.fdiv(runs.size),
      semantic_error_runs: semantic_error_runs,
      semantic_error_rate: semantic_error_runs.fdiv(runs.size),
      modes: modes,
      ms_p50: DirectivesEval::Util.percentile(elapsed, 0.50),
      ms_p95: DirectivesEval::Util.percentile(elapsed, 0.95),
      run_results: runs,
      failure_samples: failures.first(3),
    }
  end

production_auto_sampling_profile =
  ENV.fetch("OPENROUTER_PRODUCTION_AUTO_SAMPLING_PROFILE", "1") == "1"
recommended_sampling_profiles = OpenRouterSamplingProfiles::CATALOG.filter("recommended")

task_list =
  selected_models.each_with_index.flat_map do |model_entry, model_index|
    base_profiles =
      if enforce_sampling_profile_applicability
        selected_sampling_profiles.select { |p| p.applies_to_model?(model_entry.id) }
      else
        selected_sampling_profiles
      end

    base_profiles = [default_sampling_profile] if base_profiles.empty?

    requested_strategies.flat_map do |strategy|
      profiles = base_profiles

      if production_auto_sampling_profile &&
          strategy.id == DirectivesEval::Strategies::PRODUCTION.id &&
          base_profiles.length == 1 &&
          base_profiles.first.id == default_sampling_profile.id
        recommended = recommended_sampling_profiles.find { |p| p.applies_to_model?(model_entry.id) }
        profiles = [recommended] if recommended
      end

      profiles.flat_map do |profile|
        selected_language_policies.map do |language_policy|
          {
            model_entry: model_entry,
            model_index: model_index,
            sampling_profile: profile,
            strategy: strategy,
            language_policy: language_policy,
          }
        end
      end
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
  language_policy_filter: raw_language_policy_filter,
  language_policy_matrix: language_policy_matrix,
  language_policy_strict: language_policy_strict,
  language_policies: selected_language_policies.map(&:id),
  sampling_profile_filter: sampling_profile_filter,
  sampling_profiles: task_list.map { |t| t[:sampling_profile].id }.uniq,
  sampling_profile_enforce_applicability: enforce_sampling_profile_applicability,
  strategy_filter: raw_strategy_filter,
  strategy_matrix: strategy_matrix,
  strategies: requested_strategies.map(&:id),
  semantic_repair: requested_strategies.length == 1 ? requested_strategies.first.semantic_repair : nil,
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

summary_by_scenario_and_language_policy =
  all_runs.each_with_object({}) do |run, out|
    sid = run[:scenario].to_s
    lang = run[:language_policy].to_s
    lang = DirectivesEval::LanguagePolicy::OFF.id if lang.empty?

    out[lang] ||= {}
    out[lang][sid] ||= { "runs" => 0, "ok" => 0, "errors" => Hash.new(0) }
    out[lang][sid]["runs"] += 1
    out[lang][sid]["ok"] += 1 if run[:ok] == true

    unless run[:ok] == true
      cat = DirectivesEval::Util.error_category(run[:error])
      cat = "unknown" if cat.empty?
      out[lang][sid]["errors"][cat] += 1
    end
  end
summary_by_scenario_and_language_policy.each_value do |by_scenario|
  by_scenario.each_value { |v| v["errors"] = v["errors"].to_h }
end
File.write(
  out_dir.join("summary_by_scenario_and_language_policy.json"),
  JSON.pretty_generate(summary_by_scenario_and_language_policy),
)

summary_by_scenario_and_strategy =
  all_runs.each_with_object({}) do |run, out|
    strategy = run[:strategy].to_s
    strategy = DirectivesEval::Strategies::BASELINE.id if strategy.empty?
    sid = run[:scenario].to_s

    out[strategy] ||= {}
    out[strategy][sid] ||= { "runs" => 0, "ok" => 0, "errors" => Hash.new(0) }
    out[strategy][sid]["runs"] += 1
    out[strategy][sid]["ok"] += 1 if run[:ok] == true

    unless run[:ok] == true
      cat = DirectivesEval::Util.error_category(run[:error])
      cat = "unknown" if cat.empty?
      out[strategy][sid]["errors"][cat] += 1
    end
  end
summary_by_scenario_and_strategy.each_value do |by_scenario|
  by_scenario.each_value { |v| v["errors"] = v["errors"].to_h }
end
File.write(
  out_dir.join("summary_by_scenario_and_strategy.json"),
  JSON.pretty_generate(summary_by_scenario_and_strategy),
)

puts "LLM Directives Eval"
puts "ts: #{summary[:ts]}"
puts "models: #{selected_models.length}"
puts "tasks: #{reports.size}"
puts "scenarios: #{summary[:scenarios].join(",")}"
puts "trials_per_model: #{trials_per_model}"
puts "jobs: #{parallel_jobs}"
puts "require_parameters: #{require_parameters_default}"
puts "language_policy_filter: #{raw_language_policy_filter}" unless raw_language_policy_filter.strip.empty?
puts "language_policy_matrix: #{language_policy_matrix}" if language_policy_matrix
puts "language_policy_strict: #{language_policy_strict}" if language_policy_strict
puts "language_policies: #{selected_language_policies.map(&:id).join(",")}"
puts "sampling_profile_filter: #{sampling_profile_filter}"
puts "sampling_profiles: #{task_list.map { |t| t[:sampling_profile].id }.uniq.join(",")}"
puts "strategy_filter: #{raw_strategy_filter}" unless raw_strategy_filter.empty?
puts "strategy_matrix: #{strategy_matrix}" if strategy_matrix
puts "strategies: #{requested_strategies.map(&:id).join(",")}"
puts "semantic_repair: #{summary[:semantic_repair]}" unless summary[:semantic_repair].nil?
puts "full report: #{out_dir.relative_path_from(Rails.root)}"
puts

header = ["model", "profile", "strategy", "lang", "runs", "ok", "rate", "p50_ms", "p95_ms", "sample"]
rows =
  reports.map do |r|
    sample = Array(r[:failure_samples]).first
    sample_path = sample ? sample[:report].to_s : "-"
    [
      r[:model].to_s,
      r[:sampling_profile].to_s,
      r[:strategy].to_s,
      r[:language_policy].to_s,
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
