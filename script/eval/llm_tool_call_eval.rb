#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "thread"
require "time"

# Boot Bundler/Bootsnap without loading full Rails.
require_relative "../../config/boot"

require "agent_core"
require "simple_inference"

require_relative "support/openrouter_sampling_profiles"
require_relative "support/openrouter_models"
require_relative "support/paths"
require_relative "support/language_policy_prompt"
require_relative "support/agent_core_openai_provider"

module ToolCallEval
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

        candidates =
          [
            id,
            base_id,
            provider,
            *tags,
          ].map { |value| value.to_s.downcase }.uniq

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

    def entries
      @entries.dup
    end

    def ids
      @entries.map(&:id)
    end

    def filter(raw_filter)
      tokens = raw_filter.to_s.split(",").map(&:strip).reject(&:empty?)
      return entries if tokens.empty? || tokens.any? { |token| %w[all full *].include?(token.downcase) }

      include_tokens = tokens.reject { |token| token.start_with?("!") }
      exclude_tokens =
        tokens
          .select { |token| token.start_with?("!") }
          .map { |token| token.delete_prefix("!") }
          .reject(&:empty?)

      selected =
        if include_tokens.empty?
          entries
        else
          entries.select { |entry| include_tokens.any? { |token| entry.matches?(token) } }
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
      when "deepseek_openrouter_compat", "deepseek_compat"
        { message_transforms: ["assistant_tool_calls_reasoning_content_empty_if_missing"] }
      when "gemini_openrouter_compat", "gemini_compat"
        { message_transforms: ["assistant_tool_calls_signature_skip_validator_if_missing"] }
      when "content_tag_tool_call_fallback", "content_tag_fallback"
        { response_transforms: ["assistant_content_tool_call_tags_to_tool_calls"] }
      when "tool_use_disabled", "disable_tool_use", "tools_disabled"
        { tool_use_mode: :disabled }
      else
        {}
      end
    end

    def canonical_workaround_name(name)
      name.to_s.strip.downcase.tr("-", "_")
    end
  end

  DEFAULT_TOOL_CALLING = {
    tool_use_mode: :relaxed,
    fix_empty_final: true,
    fix_empty_final_disable_tools: true,
    fallback_retry_count: 0,
    message_transforms: [],
    response_transforms: [],
    request_overrides: {},
  }.freeze

  module Strategies
    Entry =
      Struct.new(
        :id,
        :apply_model_workarounds,
        :apply_infra_defaults,
        :apply_provider_defaults,
        :default_parallel_tool_calls,
        :tags,
        keyword_init: true,
      ) do
      def initialize(
        id:,
        apply_model_workarounds:,
        apply_infra_defaults:,
        apply_provider_defaults:,
        default_parallel_tool_calls:,
        tags: []
      )
        super(
          id: id.to_s,
          apply_model_workarounds: apply_model_workarounds == true,
          apply_infra_defaults: apply_infra_defaults == true,
          apply_provider_defaults: apply_provider_defaults == true,
          default_parallel_tool_calls: default_parallel_tool_calls,
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
        apply_model_workarounds: false,
        apply_infra_defaults: false,
        apply_provider_defaults: false,
        default_parallel_tool_calls: nil,
        tags: %w[raw naked unoptimized],
      ).freeze

    BASELINE =
      Entry.new(
        id: "baseline",
        apply_model_workarounds: false,
        apply_infra_defaults: true,
        apply_provider_defaults: true,
        default_parallel_tool_calls: false,
        tags: %w[base],
      ).freeze

    PRODUCTION =
      Entry.new(
        id: "production",
        apply_model_workarounds: true,
        apply_infra_defaults: true,
        apply_provider_defaults: true,
        default_parallel_tool_calls: false,
        tags: %w[prod recommended],
      ).freeze

    MATRIX_CATALOG = [BASELINE, PRODUCTION].freeze
    ALL = [RAW, BASELINE, PRODUCTION].freeze

    module_function

    def filter(raw_filter)
      tokens = raw_filter.to_s.split(",").map(&:strip).reject(&:empty?)
      return [PRODUCTION] if tokens.empty?

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
      latin_word_count = t.scan(/[A-Za-z]{2,}/).length

      case lang
      when "ja-JP"
        return "ok" if has_kana
        return "unknown" if has_han
        return "drift" if has_hangul
        return "drift" if latin_word_count >= 3

        "unknown"
      when "zh-CN", "zh-TW", "yue-HK"
        return "drift" if has_kana
        return "ok" if has_han
        return "drift" if has_hangul
        return "drift" if latin_word_count >= 3

        "unknown"
      when "ko-KR"
        return "ok" if has_hangul
        return "unknown" if has_han
        return "drift" if has_kana
        return "drift" if latin_word_count >= 3

        "unknown"
      when "en-US"
        return "ok" if latin_word_count >= 1
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

# OpenRouter is OpenAI-compatible. SimpleInference will compose:
#   base_url + api_prefix + endpoint
#
# Use base_url without /v1 (recommended), or include /v1 if you prefer.
# SimpleInference will avoid the common "/v1/v1" footgun automatically.
base_url = ENV.fetch("OPENROUTER_BASE_URL", "https://openrouter.ai/api")
api_prefix = ENV.fetch("OPENROUTER_API_PREFIX", "/v1")
fix_empty_final = ENV.fetch("OPENROUTER_FIX_EMPTY_FINAL", "1") == "1"
tool_use_mode =
  ENV.fetch("OPENROUTER_TOOL_USE_MODE", "enforced").strip.downcase
tool_use_mode = "disabled" unless %w[enforced relaxed disabled].include?(tool_use_mode)
tool_failure_policy =
  ENV.fetch("OPENROUTER_TOOL_FAILURE_POLICY", "fatal").strip.downcase
tool_failure_policy = "fatal" unless %w[fatal tolerated].include?(tool_failure_policy)
tools_enabled = tool_use_mode != "disabled"
fallback_retry_count =
  begin
    Integer(ENV.fetch("OPENROUTER_TOOL_CALLING_FALLBACK_RETRY_COUNT", "0"))
  rescue ArgumentError
    0
  end
fallback_retry_count = 0 if fallback_retry_count < 0
tool_allowlist =
  ENV.fetch("OPENROUTER_TOOL_ALLOWLIST", "")
    .split(",")
    .map(&:strip)
    .reject(&:empty?)
if tool_allowlist.any? { |n| %w[all full *].include?(n.to_s.strip.downcase) }
  tool_allowlist = nil
elsif tool_allowlist.empty? && tools_enabled
  tool_allowlist = %w[state_get state_patch]
elsif tool_allowlist.empty?
  tool_allowlist = nil
end
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

verbose_level =
  begin
    Integer(ENV.fetch("VERBOSE", "1"))
  rescue ArgumentError, TypeError
    1
  end
verbose_level = 0 if verbose_level < 0

empty_response_retry_count =
  begin
    Integer(ENV.fetch("OPENROUTER_EMPTY_RESPONSE_RETRY_COUNT", "1"))
  rescue ArgumentError, TypeError
    1
  end
empty_response_retry_count = 0 if empty_response_retry_count < 0
enable_content_tag_tool_call_fallback = ENV.fetch("OPENROUTER_ENABLE_CONTENT_TAG_TOOL_CALL_FALLBACK", "0") == "1"
fallback_matrix = ENV.fetch("OPENROUTER_FALLBACK_MATRIX", "0") == "1"

strategy_matrix = ENV.fetch("OPENROUTER_STRATEGY_MATRIX", "0") == "1"
raw_strategy_filter = ENV.fetch("OPENROUTER_STRATEGY_FILTER", "").to_s.strip

requested_strategies =
  if strategy_matrix
    ToolCallEval::Strategies::MATRIX_CATALOG.dup
  else
    ToolCallEval::Strategies.filter(raw_strategy_filter)
  end

if requested_strategies.empty?
  warn(
    "No strategies selected from OPENROUTER_STRATEGY_FILTER=#{raw_strategy_filter.inspect}. " \
    "Falling back to #{ToolCallEval::Strategies::PRODUCTION.id.inspect}.",
  )
  requested_strategies = [ToolCallEval::Strategies::PRODUCTION]
end

client_timeout =
  begin
    Float(ENV.fetch("OPENROUTER_CLIENT_TIMEOUT", "120"))
  rescue ArgumentError, TypeError
    120.0
  end
client_timeout = nil if client_timeout <= 0

client_open_timeout =
  begin
    Float(ENV.fetch("OPENROUTER_OPEN_TIMEOUT", "10"))
  rescue ArgumentError, TypeError
    10.0
  end
client_open_timeout = nil if client_open_timeout <= 0

client_read_timeout =
  begin
    raw = ENV.fetch("OPENROUTER_READ_TIMEOUT", "").to_s.strip
    raw.empty? ? nil : Float(raw)
  rescue ArgumentError, TypeError
    nil
  end
client_read_timeout = nil if client_read_timeout && client_read_timeout <= 0
client_read_timeout ||= client_timeout

http_adapter_name = ENV.fetch("OPENROUTER_HTTP_ADAPTER", "httpx").to_s.strip.downcase.tr("-", "_")
unless ["", "default", "net_http", "nethttp", "httpx"].include?(http_adapter_name)
  warn "Unknown OPENROUTER_HTTP_ADAPTER=#{http_adapter_name.inspect}. Using httpx."
  http_adapter_name = "httpx"
end

build_http_adapter =
  lambda do
    case http_adapter_name
    when "", "default", "net_http", "nethttp"
      nil
    when "httpx"
      SimpleInference::HTTPAdapters::HTTPX.new(timeout: client_timeout)
    end
  end

MODEL_CATALOG =
  ToolCallEval::ModelCatalog.build do
    VibeTavernEval::OpenRouterModels.entries.each do |entry|
      model entry.id, workarounds: entry.workarounds_for(:tool_call), tags: entry.tags
    end
  end

DEFAULT_MODELS = MODEL_CATALOG.ids.freeze

model_filter = ENV.fetch("OPENROUTER_MODEL_FILTER", "stable")
selected_model_entries = MODEL_CATALOG.filter(model_filter)

if selected_model_entries.empty?
  warn "No models matched OPENROUTER_MODEL_FILTER=#{model_filter.inspect}."
  warn "Available model ids: #{DEFAULT_MODELS.join(", ")}"
  exit 2
end

sampling_profile_filter =
  ENV.fetch("OPENROUTER_SAMPLING_PROFILE_FILTER", OpenRouterSamplingProfiles::DEFAULT_PROFILE_ID)
enforce_sampling_profile_applicability =
  ENV.fetch("OPENROUTER_SAMPLING_PROFILE_ENFORCE_APPLICABILITY", "1") == "1"

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

llm_options_defaults_overrides = {}
if (raw = ENV.fetch("OPENROUTER_LLM_OPTIONS_DEFAULTS_JSON", "").to_s.strip).length.positive?
  begin
    parsed = JSON.parse(raw)
    llm_options_defaults_overrides.merge!(parsed) if parsed.is_a?(Hash)
  rescue JSON::ParserError
    warn "Invalid OPENROUTER_LLM_OPTIONS_DEFAULTS_JSON (must be a JSON object). Ignoring."
  end
end

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

headers = {}
headers["HTTP-Referer"] = ENV["OPENROUTER_HTTP_REFERER"] if ENV["OPENROUTER_HTTP_REFERER"]
headers["X-Title"] = ENV["OPENROUTER_X_TITLE"] if ENV["OPENROUTER_X_TITLE"]

# Optional OpenRouter request-level knobs (OpenAI-compatible).
# These are injected via context[:tool_calling][:request_overrides] so the lower
# layers (pipeline/client) stay provider-agnostic.
base_request_overrides = {}

if (route = ENV["OPENROUTER_ROUTE"].to_s.strip).length.positive?
  base_request_overrides[:route] = route
end

if (raw = ENV["OPENROUTER_TRANSFORMS"])
  transforms =
    case raw.to_s.strip.downcase
    when "", "auto"
      nil
    when "none", "off", "0", "false"
      []
    else
      raw.split(",").map(&:strip).reject(&:empty?)
    end

  base_request_overrides[:transforms] = transforms if transforms
end

provider = {}
%w[ONLY ORDER IGNORE].each do |key|
  env_key = "OPENROUTER_PROVIDER_#{key}"
  next unless ENV.key?(env_key)

  raw = ENV[env_key].to_s
  values = raw.split(",").map(&:strip).reject(&:empty?)
  provider[key.downcase.to_sym] = values if values.any?
end
base_request_overrides[:provider] = provider if provider.any?

if (raw = ENV["OPENROUTER_REQUEST_OVERRIDES_JSON"].to_s.strip).length.positive?
  begin
    parsed = JSON.parse(raw)
    base_request_overrides.merge!(deep_symbolize_keys(parsed)) if parsed.is_a?(Hash)
  rescue JSON::ParserError
    warn "Invalid OPENROUTER_REQUEST_OVERRIDES_JSON (must be a JSON object). Ignoring."
  end
end

build_provider_tool_calling_preset =
  lambda do |apply_provider_defaults:, enable_tag_fallback:|
    return {} unless apply_provider_defaults == true
    return {} unless enable_tag_fallback == true

    { response_transforms: ["assistant_content_tool_call_tags_to_tool_calls"] }
  end

fallback_profiles =
  if fallback_matrix
    [
      { id: "fallback_off", content_tag_tool_call_fallback: false },
      { id: "fallback_on", content_tag_tool_call_fallback: true },
    ]
  else
    [
      { id: "best_effort", content_tag_tool_call_fallback: enable_content_tag_tool_call_fallback },
    ]
  end

module ToolCallEval
  class Workspace
    attr_reader :id, :facts, :draft, :locks, :ui_state

    def initialize(id: nil, facts: nil, draft: nil, locks: nil, ui_state: nil)
      @id = (id || SecureRandom.uuid).to_s
      @facts = facts.is_a?(Hash) ? deep_dup(facts) : {}
      @draft = draft.is_a?(Hash) ? deep_dup(draft) : {}
      @locks = Array(locks).map(&:to_s)
      @ui_state = ui_state.is_a?(Hash) ? deep_dup(ui_state) : {}
      @facts_version = 0
      @draft_version = 0
    end

    def facts_etag = "facts:#{@facts_version}"
    def draft_etag = "draft:#{@draft_version}"

    def snapshot(select: nil)
      full = {
        "facts" => deep_dup(@facts),
        "draft" => deep_dup(@draft),
        "locks" => { "paths" => @locks.dup },
        "ui_state" => deep_dup(@ui_state),
        "versions" => { "facts_etag" => facts_etag, "draft_etag" => draft_etag },
      }

      paths = Array(select).map(&:to_s).reject(&:empty?)
      return full if paths.empty?

      paths.each_with_object({}) do |pointer, out|
        out[pointer] = read_pointer(full, pointer)
      rescue ArgumentError, KeyError, IndexError
        out[pointer] = nil
      end
    end

    def patch_draft!(ops, etag: nil)
      raise ArgumentError, "etag mismatch" if etag && etag.to_s != draft_etag

      applied = 0
      before = deep_dup(@draft)

      begin
        Array(ops).each do |op|
          op = op.is_a?(Hash) ? op : {}

          action = op["op"].to_s
          path = op["path"].to_s
          value = op.key?("value") ? op["value"] : nil
          index = op["index"]

          raise ArgumentError, "path must start with /draft/" unless path.start_with?("/draft/")

          case action
          when "set"
            write_pointer!(@draft, path.delete_prefix("/draft"), value)
            applied += 1
          when "delete"
            delete_pointer!(@draft, path.delete_prefix("/draft"))
            applied += 1
          when "append"
            append_pointer!(@draft, path.delete_prefix("/draft"), value)
            applied += 1
          when "insert"
            insert_pointer!(@draft, path.delete_prefix("/draft"), index, value)
            applied += 1
          else
            raise ArgumentError, "unknown op: #{action.inspect}"
          end
        end
      rescue StandardError
        # Patch operations are atomic: roll back on any failure.
        @draft = before
        raise
      end

      @draft_version += 1 if applied.positive?

      { "draft_etag" => draft_etag, "applied" => applied }
    end

    private

    # Very small JSON Pointer helpers (enough for eval).
    def read_pointer(doc, pointer)
      raise ArgumentError, "pointer must start with /" unless pointer.to_s.start_with?("/")

      tokens = pointer.split("/").drop(1).map { |t| unescape_pointer_token(t) }
      tokens.reduce(doc) do |cur, tok|
        case cur
        when Hash
          cur.fetch(tok)
        when Array
          cur.fetch(Integer(tok))
        else
          raise ArgumentError, "cannot descend into #{cur.class}"
        end
      end
    end

    def write_pointer!(doc, pointer, value)
      pointer = pointer.to_s
      return doc.replace(value) if pointer.empty? || pointer == "/"

      raise ArgumentError, "pointer must start with /" unless pointer.start_with?("/")

      tokens = pointer.split("/").drop(1).map { |t| unescape_pointer_token(t) }
      last = tokens.pop
      parent = tokens.reduce(doc) { |cur, tok| descend_write!(cur, tok) }

      case parent
      when Hash
        parent[last] = value
      when Array
        parent[Integer(last)] = value
      else
        raise ArgumentError, "cannot write into #{parent.class}"
      end
    end

    def delete_pointer!(doc, pointer)
      raise ArgumentError, "pointer must start with /" unless pointer.to_s.start_with?("/")

      tokens = pointer.split("/").drop(1).map { |t| unescape_pointer_token(t) }
      last = tokens.pop
      parent = tokens.reduce(doc) { |cur, tok| descend_write!(cur, tok) }

      case parent
      when Hash
        parent.delete(last)
      when Array
        parent.delete_at(Integer(last))
      else
        raise ArgumentError, "cannot delete from #{parent.class}"
      end
    end

    def append_pointer!(doc, pointer, value)
      arr = read_pointer(doc, pointer)
      raise ArgumentError, "target is not an Array" unless arr.is_a?(Array)

      arr << value
    rescue KeyError
      write_pointer!(doc, pointer, [value])
    end

    def insert_pointer!(doc, pointer, index, value)
      arr = read_pointer(doc, pointer)
      raise ArgumentError, "target is not an Array" unless arr.is_a?(Array)

      i = Integer(index)
      arr.insert(i, value)
    rescue KeyError
      write_pointer!(doc, pointer, [value])
    end

    def descend_write!(cur, tok)
      case cur
      when Hash
        cur[tok] ||= {}
        cur[tok]
      when Array
        idx = Integer(tok)
        cur[idx] ||= {}
        cur[idx]
      else
        raise ArgumentError, "cannot descend into #{cur.class}"
      end
    end

    def unescape_pointer_token(token)
      token.to_s.gsub("~1", "/").gsub("~0", "~")
    end

    def deep_dup(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(k, v), out|
          kk = k.is_a?(String) ? k.dup : k
          out[kk] = deep_dup(v)
        end
      when Array
        obj.map { |v| deep_dup(v) }
      when String
        obj.dup
      else
        obj.dup
      end
    rescue TypeError
      obj
    end
  end

  class Executor
    # Keep the patch surface tiny for cross-model reliability in eval.
    MODEL_ALLOWED_STATE_PATCH_PATHS = ["/draft/foo"].freeze

    def initialize(workspace:)
      @workspace = workspace
    end

    def call(name:, args:)
      args = args.is_a?(Hash) ? args : {}

      workspace_id = args["workspace_id"].to_s
      # For eval robustness across models, treat missing/placeholder IDs as implicit.
      workspace_id = @workspace.id if workspace_id.empty? || workspace_id == "workspace_id"

      if workspace_id != @workspace.id
        return error_envelope(name, code: "WORKSPACE_NOT_FOUND", message: "Unknown workspace_id: #{workspace_id}")
      end

      case name
      when "state_get"
        select = normalize_state_get_select(args["select"])
        ok_envelope(name, "snapshot" => @workspace.snapshot(select: select))
      when "state_patch"
        ops = args["ops"]
        unless ops.is_a?(Array) && ops.any?
          return error_envelope(name, code: "ARGUMENT_ERROR", message: "ops must be a non-empty Array")
        end

        unless model_allowed_state_patch_ops?(ops)
          return error_envelope(
            name,
            code: "ARGUMENT_ERROR",
            message: "Only set on #{MODEL_ALLOWED_STATE_PATCH_PATHS.join(", ")} is allowed",
          )
        end

        result = @workspace.patch_draft!(ops, etag: nil)
        ok_envelope(name, result)
      else
        error_envelope(name, code: "TOOL_NOT_IMPLEMENTED", message: "Tool not implemented: #{name}")
      end
    rescue ArgumentError => e
      error_envelope(name, code: "ARGUMENT_ERROR", message: e.message)
    rescue StandardError => e
      error_envelope(name, code: "INTERNAL_ERROR", message: "#{e.class}: #{e.message}")
    end

    private

    def ok_envelope(name, data)
      {
        ok: true,
        tool_name: name,
        data: data.is_a?(Hash) ? data : { value: data },
        warnings: [],
        errors: [],
      }
    end

    def error_envelope(name, code:, message:)
      {
        ok: false,
        tool_name: name,
        data: {},
        warnings: [],
        errors: [{ code: code, message: message.to_s }],
      }
    end

    def normalize_state_get_select(value)
      list = Array(value).map { |v| v.to_s.strip }.reject(&:empty?)
      return nil if list.empty?

      list
        .map do |item|
          s = item.to_s.strip
          s = s.sub(/\A["'`]+\s*/, "").sub(/\s*["'`]+\z/, "")
          s = s.delete_prefix("#") if s.start_with?("#/")
          s.start_with?("/") ? s : "/#{s}"
        end
        .reject(&:empty?)
        .uniq
    end

    def model_allowed_state_patch_ops?(ops)
      ops.all? do |op|
        op.is_a?(Hash) &&
          op["op"].to_s == "set" &&
          MODEL_ALLOWED_STATE_PATCH_PATHS.include?(op["path"].to_s)
      end
    end
  end

  class AllowlistPolicy < AgentCore::Resources::Tools::Policy::Base
    def initialize(allowlist:)
      @allowlist =
        Array(allowlist)
          .map { |v| v.to_s.strip }
          .reject(&:empty?)
          .to_h { |name| [name, true] }
    end

    def authorize(name:, arguments: {}, context: {})
      _ = arguments
      _ = context

      return AgentCore::Resources::Tools::Policy::Decision.allow if @allowlist.empty?

      if @allowlist.key?(name.to_s)
        AgentCore::Resources::Tools::Policy::Decision.allow
      else
        AgentCore::Resources::Tools::Policy::Decision.deny(reason: "TOOL_NOT_ALLOWED")
      end
    end
  end

  class AgentCoreRunner < AgentCore::PromptRunner::Runner
    private

    def tool_error_envelope(tool_name, code:, message:)
      {
        ok: false,
        tool_name: tool_name.to_s,
        data: {},
        warnings: [],
        errors: [{ code: code.to_s, message: message.to_s }],
      }
    end

    def tool_error_result(tool_name, code:, message:)
      json = JSON.generate(tool_error_envelope(tool_name, code: code, message: message))
      AgentCore::Resources::Tools::ToolResult.error(text: json)
    rescue StandardError
      AgentCore::Resources::Tools::ToolResult.error(text: "#{code}: #{message}")
    end

    def execute_tool_calls(tool_calls:, tools_registry:, tool_policy:, events:, tool_calls_record:, max_tool_output_bytes:, stream_block:)
      tool_calls.map do |tc|
        stream_block&.call(AgentCore::StreamEvent::ToolExecutionStart.new(
          tool_call_id: tc.id, name: tc.name, arguments: tc.arguments
        ))
        events.emit(:tool_call, tc.name, tc.arguments, tc.id)

        if tc.respond_to?(:arguments_valid?) && !tc.arguments_valid?
          parse_error = tc.respond_to?(:arguments_parse_error) ? tc.arguments_parse_error : :invalid_json

          code =
            case parse_error
            when :too_large then "ARGUMENTS_TOO_LARGE"
            else "INVALID_JSON"
            end

          error_text =
            case parse_error
            when :too_large
              "Tool call arguments are too large. Retry with smaller arguments."
            else
              "Invalid JSON in tool call arguments. Retry with arguments as a JSON object only."
            end

          error_result = tool_error_result(tc.name, code: code, message: error_text)

          stream_block&.call(AgentCore::StreamEvent::ToolExecutionEnd.new(
            tool_call_id: tc.id, name: tc.name, result: error_result, error: true
          ))
          events.emit(:tool_result, tc.name, error_result, tc.id)
          tool_calls_record << { name: tc.name, arguments: tc.arguments, error: code }

          next tool_result_to_message(
            error_result,
            tool_call_id: tc.id,
            name: tc.name,
            max_tool_output_bytes: max_tool_output_bytes,
          )
        end

        if tool_policy
          decision = tool_policy.authorize(name: tc.name, arguments: tc.arguments)
          unless decision.allowed?
            error_result = tool_error_result(tc.name, code: "TOOL_DENIED", message: "Tool call denied: #{decision.reason}")

            stream_block&.call(AgentCore::StreamEvent::ToolExecutionEnd.new(
              tool_call_id: tc.id, name: tc.name, result: error_result, error: true
            ))
            events.emit(:tool_result, tc.name, error_result, tc.id)
            tool_calls_record << { name: tc.name, arguments: tc.arguments, error: decision.reason }

            next tool_result_to_message(
              error_result,
              tool_call_id: tc.id,
              name: tc.name,
              max_tool_output_bytes: max_tool_output_bytes,
            )
          end
        end

        requested_name = tc.name.to_s
        execute_name = requested_name
        unless tools_registry.include?(execute_name)
          if execute_name.include?(".")
            underscored = execute_name.tr(".", "_")
            execute_name = underscored if tools_registry.include?(underscored)
          end
        end

        result = begin
          tools_registry.execute(name: execute_name, arguments: tc.arguments)
        rescue AgentCore::ToolNotFoundError => e
          tool_error_result(requested_name, code: "TOOL_NOT_FOUND", message: e.message)
        rescue StandardError => e
          tool_error_result(requested_name, code: "TOOL_RAISED", message: e.message)
        end

        result = limit_tool_result(result, max_bytes: max_tool_output_bytes, tool_name: execute_name)

        stream_block&.call(AgentCore::StreamEvent::ToolExecutionEnd.new(
          tool_call_id: tc.id, name: tc.name, result: result, error: result.error?
        ))
        events.emit(:tool_result, tc.name, result, tc.id)

        tool_calls_record << {
          name: requested_name,
          executed_name: execute_name,
          arguments: tc.arguments,
          error: result.error? ? result.text : nil,
        }

        tool_result_to_message(
          result,
          tool_call_id: tc.id,
          name: requested_name,
          max_tool_output_bytes: max_tool_output_bytes,
        )
      end
    end
  end

  def self.build_tools(executor:, max_tool_output_bytes:)
    max_tool_output_bytes = Integer(max_tool_output_bytes)

    [
      AgentCore::Resources::Tools::Tool.new(
        name: "state_get",
        description:
          "Read workspace state (facts/draft/locks/ui_state/versions). " \
          "`select` is optional and may include JSON pointers like `/draft` or `/draft/foo`.",
        parameters: {
          type: "object",
          additionalProperties: false,
          properties: {
            workspace_id: { type: "string" },
            select: {
              type: "array",
              description: "Optional JSON pointers to select (e.g. `/facts`, `/draft`, `/ui_state`).",
              items: { type: "string" },
            },
          },
          required: [],
        },
        metadata: { exposed_to_model: true },
      ) do |arguments, context:|
        _ = context

        envelope = executor.call(name: "state_get", args: arguments)
        json = JSON.generate(envelope)

        if json.bytesize > max_tool_output_bytes
          err = {
            ok: false,
            tool_name: "state_get",
            data: {},
            warnings: [],
            errors: [
              {
                code: "TOOL_OUTPUT_TOO_LARGE",
                message: "Tool output exceeded max_bytes=#{max_tool_output_bytes}.",
              },
            ],
          }
          return AgentCore::Resources::Tools::ToolResult.error(text: JSON.generate(err))
        end

        AgentCore::Resources::Tools::ToolResult.success(text: json)
      end,
      AgentCore::Resources::Tools::Tool.new(
        name: "state_patch",
        description: "Apply patch operations to draft state (set/delete/append/insert).",
        parameters: {
          type: "object",
          additionalProperties: false,
          properties: {
            workspace_id: { type: "string" },
            request_id: { type: "string" },
            ops: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                properties: {
                  op: { type: "string" },
                  path: { type: "string" },
                  value: {},
                  index: { type: "integer" },
                },
                required: ["op", "path"],
              },
            },
          },
          required: ["request_id", "ops"],
        },
        metadata: { exposed_to_model: true },
      ) do |arguments, context:|
        _ = context

        envelope = executor.call(name: "state_patch", args: arguments)
        AgentCore::Resources::Tools::ToolResult.success(text: JSON.generate(envelope))
      end,
      # Include but hide (regression guard): model should never see it.
      AgentCore::Resources::Tools::Tool.new(
        name: "facts_commit",
        description: "Commit a facts proposal (must be triggered by UI/user confirmation).",
        parameters: {
          type: "object",
          additionalProperties: false,
          properties: {
            workspace_id: { type: "string" },
            request_id: { type: "string" },
            proposal_id: { type: "string" },
            user_confirmed: { type: "boolean" },
          },
          required: ["workspace_id", "request_id", "proposal_id", "user_confirmed"],
        },
        metadata: { exposed_to_model: false },
      ) do |_arguments, context:|
        _ = context

        err = {
          ok: false,
          tool_name: "facts_commit",
          data: {},
          warnings: [],
          errors: [{ code: "TOOL_NOT_AVAILABLE", message: "facts_commit is not available." }],
        }
        AgentCore::Resources::Tools::ToolResult.error(text: JSON.generate(err))
      end,
    ]
  end
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

def normalize_string_list(value)
  list = Array(value).map { |v| v.to_s.strip }.reject(&:empty?)
  list.empty? ? nil : list
end

def explicit_empty_string_list?(value)
  case value
  when String
    value.split(",").map(&:strip).reject(&:empty?).empty?
  when Array
    value.map { |v| v.to_s.strip }.reject(&:empty?).empty?
  else
    false
  end
end

def merge_string_list(left, right)
  return nil if right.nil?

  right_list = normalize_string_list(right)
  return [] if explicit_empty_string_list?(right)

  left_list = normalize_string_list(left)
  return right_list if left_list.nil?

  (left_list + right_list).uniq
end

def merge_tool_calling_configs(*configs)
  Array(configs).compact.reduce({}) do |acc, raw_cfg|
    cfg = raw_cfg.is_a?(Hash) ? deep_symbolize_keys(raw_cfg) : {}

    cfg.each do |k, v|
      key = k.to_sym

      case key
      when :request_overrides
        acc[key] = deep_merge_hashes(acc[key], v)
      when :tool_allowlist, :tool_denylist, :message_transforms, :response_transforms, :tool_call_transforms, :tool_result_transforms
        merged = merge_string_list(acc[key], v)
        acc[key] = merged unless merged.nil?
      else
        acc[key] = v
      end
    end

    acc
  end
end

def truncate(str, max_chars: 220)
  s = str.to_s
  return s if s.length <= max_chars

  "#{s[0, max_chars]}…"
end

def done_text?(text)
  normalized = text.to_s.strip
  normalized = normalized.sub(/\A["'`]+\s*/, "").sub(/\s*["'`]+\z/, "")
  normalized.match?(/\Adone[.!]?\z/i)
end

def localized_done_text(target_lang)
  lang = ToolCallEval::LanguagePolicy.canonical_target_lang(target_lang)

  case lang
  when "zh-CN", "zh-TW", "yue-HK"
    "已完成。"
  when "ja-JP"
    "完了です。"
  when "ko-KR"
    "완료했습니다."
  when "en-US"
    "Done."
  else
    "Done."
  end
rescue StandardError
  "Done."
end

def final_answer_ok?(text, language_policy_enabled:, target_lang:)
  if language_policy_enabled
    !text.to_s.strip.empty?
  else
    done_text?(text)
  end
end

def final_answer_failure_reason(language_policy_enabled:, target_lang:)
  if language_policy_enabled
    "assistant_text is blank (expected #{target_lang})"
  else
    %(assistant_text != "Done.")
  end
end

def error_category(message, status: nil)
  msg = message.to_s
  return "EMPTY_ASSISTANT_TEXT" if msg.start_with?("EMPTY_ASSISTANT_TEXT")
  return "CONNECTION_ERROR" if msg.start_with?("CONNECTION_ERROR:")
  return "TIMEOUT_ERROR" if msg.start_with?("TIMEOUT_ERROR:")
  return "DECODE_ERROR" if msg.start_with?("DECODE_ERROR:")
  return "ASSERTION_FAILED" if msg.start_with?("ASSERTION_FAILED:")
  return "LANGUAGE_DRIFT" if msg.start_with?("LANGUAGE_DRIFT:")
  return "NO_TOOL_CALLS" if msg.start_with?("NO_TOOL_CALLS:")
  return "TOOL_ERROR" if msg.start_with?("TOOL_ERROR:")
  return "NO_TOOL_USE_ENDPOINT" if msg.include?("No endpoints found that support tool use")
  return "TIMEOUT" if msg.include?("TimeoutError") || msg.include?("Net::ReadTimeout") || msg.match?(/Timed out after/i)

  case status.to_i
  when 401 then "AUTH"
  when 402 then "PAYMENT_REQUIRED"
  when 403 then "FORBIDDEN"
  when 404 then "NOT_FOUND"
  when 408 then "TIMEOUT"
  when 409 then "CONFLICT"
  when 413 then "REQUEST_TOO_LARGE"
  when 422 then "UNPROCESSABLE"
  when 429 then "RATE_LIMIT"
  when 500..599 then "UPSTREAM_5XX"
  else
    status ? "HTTP_#{status}" : "EXCEPTION"
  end
end

def normalize_tool_use_mode(value)
  s = value.to_s.strip.downcase.tr("-", "_")

  case s
  when "enforced", "required", "must"
    "enforced"
  when "relaxed", "preferred", "optional"
    "relaxed"
  when "disabled", "off", "none", "0", "false"
    "disabled"
  else
    s.empty? ? "relaxed" : s
  end
end

def provider_error_hint(report)
  body = report[:error_body]
  return nil unless body.is_a?(Hash)

  provider = body.dig("error", "metadata", "provider_name").to_s
  raw = body.dig("error", "metadata", "raw")

  raw_msg =
    case raw
    when String
      begin
        parsed = JSON.parse(raw)
        case parsed
        when Hash
          err = parsed["error"]
          if err.is_a?(Hash)
            err["message"] || parsed["message"] || raw
          elsif err.is_a?(String)
            err
          else
            parsed["message"] || raw
          end
        when String
          parsed
        when Array
          first_hash = parsed.find { |v| v.is_a?(Hash) }
          if first_hash
            err = first_hash["error"]
            if err.is_a?(Hash)
              err["message"] || first_hash["message"] || raw
            elsif err.is_a?(String)
              err
            else
              first_hash["message"] || raw
            end
          else
            raw
          end
        else
          raw
        end
      rescue JSON::ParserError
        raw
      end
    else
      nil
    end

  parts = []
  parts << provider unless provider.empty?
  parts << raw_msg.to_s unless raw_msg.to_s.empty?
  return nil if parts.empty?

  parts.join(": ")
rescue StandardError
  nil
end

chat_only_scenario = {
  id: "chat_only",
  title: "Tool calling disabled (control)",
  context_overrides: { tool_use_mode: :disabled, request_overrides: { max_tokens: 32 } },
  prepare: ->(_workspace) { },
  system: <<~SYS.strip,
    Tool calling is disabled for this run.
    Do not call any tools.
    Reply exactly with: Done.
  SYS
  user_text: ->(_workspace) { "Reply exactly with: Done." },
  assert: lambda { |assistant_text:, language_policy_enabled:, language_policy_target_lang:, **|
    return [] if final_answer_ok?(assistant_text, language_policy_enabled: language_policy_enabled, target_lang: language_policy_target_lang)

    [final_answer_failure_reason(language_policy_enabled: language_policy_enabled, target_lang: language_policy_target_lang)]
  },
}.freeze

SCENARIOS =
  if tools_enabled
    [
      {
        id: "happy_path",
        title: "Happy path (get -> patch -> done)",
        context_overrides: {},
        prepare: ->(_workspace) { },
        system: <<~SYS.strip,
          You are a tool-using assistant.
          Rules:
          - Always call `state_get` first.
          - IMPORTANT: Call at most ONE tool per assistant message. Do NOT call multiple tools in a single response.
          - Then call `state_patch` to set `/draft/foo` to string value "bar".
            - Only change the `/draft/foo` path. Do not change other draft keys.
          - Do NOT ask the user for confirmation. The target value is always "bar", and it is already approved.
          - If a tool returns ok=false, read `errors[]`, fix your arguments, and call the tool again.
          - Do NOT reply "Done." until AFTER you have received a successful (ok=true) tool result for `state_patch`.
          - Do NOT call `facts_commit` (it is not available).
          - After tools are done, reply with a single sentence: "Done."

          Examples (JSON args):
          - state_get: {"workspace_id":"..."}
          - state_patch: {"request_id":"r1","ops":[{"op":"set","path":"/draft/foo","value":"bar"}]}
        SYS
        user_text: ->(workspace) { "workspace_id=#{workspace.id}" },
        assert: lambda { |assistant_text:, workspace:, tools_enabled:, language_policy_enabled:, language_policy_target_lang:, **|
          reasons = []
          unless final_answer_ok?(
            assistant_text,
            language_policy_enabled: language_policy_enabled,
            target_lang: language_policy_target_lang,
          )
            reasons << final_answer_failure_reason(language_policy_enabled: language_policy_enabled, target_lang: language_policy_target_lang)
          end
          reasons << %(draft["foo"] != "bar") if tools_enabled && workspace.draft["foo"] != "bar"
          reasons
        },
      },
      {
        id: "partial_success_failure",
        title: "Partial success (state_get ok) + failure (bad state_patch) + recovery",
        context_overrides: { request_overrides: { parallel_tool_calls: true } },
        prepare: ->(_workspace) { },
        system: <<~SYS.strip,
          You are a tool-using assistant.
          Rules:
          - In your FIRST assistant response, call BOTH tools in a single message:
            1) `state_get` (valid arguments)
            2) `state_patch` BUT intentionally use an INVALID path (NOT /draft/foo) so it returns ok=false with ARGUMENT_ERROR.
          - After you receive tool results, call `state_patch` again with the CORRECT arguments to set `/draft/foo` to "bar".
          - IMPORTANT: Call at most ONE tool per assistant message after the first response.
          - After a successful `state_patch`, reply with a single sentence: "Done."
        SYS
        user_text: ->(workspace) { "workspace_id=#{workspace.id}" },
        assert: lambda { |assistant_text:, workspace:, tools_enabled:, trace:, language_policy_enabled:, language_policy_target_lang:, **|
          reasons = []
          unless final_answer_ok?(
            assistant_text,
            language_policy_enabled: language_policy_enabled,
            target_lang: language_policy_target_lang,
          )
            reasons << final_answer_failure_reason(language_policy_enabled: language_policy_enabled, target_lang: language_policy_target_lang)
          end
          reasons << %(draft["foo"] != "bar") if tools_enabled && workspace.draft["foo"] != "bar"

          saw_mixed =
            Array(trace).any? do |t|
              t.is_a?(Hash) &&
                Array(t[:tool_results]).any? { |r| r.is_a?(Hash) && r[:name].to_s == "state_get" && r[:ok] == true } &&
                Array(t[:tool_results]).any? { |r| r.is_a?(Hash) && r[:name].to_s == "state_patch" && r[:ok] == false }
            end
          reasons << "expected at least one turn with mixed tool results (ok + fail)" if tools_enabled && !saw_mixed

          reasons
        },
      },
      {
        id: "missing_workspace_id",
        title: "Missing workspace_id (implicit context)",
        context_overrides: {},
        prepare: ->(_workspace) { },
        system: <<~SYS.strip,
          You are a tool-using assistant.
          Rules:
          - Always call `state_get` first, but DO NOT pass `workspace_id` in its arguments.
          - IMPORTANT: Call at most ONE tool per assistant message. Do NOT call multiple tools in a single response.
          - Then call `state_patch` to set `/draft/foo` to string value "bar".
            - Do NOT pass `workspace_id` in tool arguments.
            - Only change the `/draft/foo` path. Do not change other draft keys.
            - The value must be exactly "bar". Never copy `workspace_id` into `/draft/foo`.
          - If a tool returns ok=false, read `errors[]`, fix your arguments, and call the tool again.
          - After tools are done, reply with a single sentence: "Done."

          Examples (JSON args):
          - state_get: {}
          - state_patch: {"request_id":"r1","ops":[{"op":"set","path":"/draft/foo","value":"bar"}]}
        SYS
        user_text: ->(workspace) { "workspace_id=#{workspace.id}" },
        assert: lambda { |assistant_text:, workspace:, tools_enabled:, language_policy_enabled:, language_policy_target_lang:, **|
          reasons = []
          unless final_answer_ok?(
            assistant_text,
            language_policy_enabled: language_policy_enabled,
            target_lang: language_policy_target_lang,
          )
            reasons << final_answer_failure_reason(language_policy_enabled: language_policy_enabled, target_lang: language_policy_target_lang)
          end
          reasons << %(draft["foo"] != "bar") if tools_enabled && workspace.draft["foo"] != "bar"
          reasons
        },
      },
      {
        id: "type_error_recovery",
        title: "Type error recovery (ops must be Array)",
        context_overrides: {},
        prepare: ->(_workspace) { },
        system: <<~SYS.strip,
          You are a tool-using assistant.
          Rules:
          - Always call `state_get` first.
          - IMPORTANT: Call at most ONE tool per assistant message.
          - Then call `state_patch` to set `/draft/foo` to string value "bar".
            - Note: `ops` MUST be an Array; if you send the wrong type, the tool will return ok=false with ARGUMENT_ERROR.
          - If a tool returns ok=false, read `errors[]`, fix your arguments, and call the tool again.
          - Do NOT reply "Done." until AFTER you have received a successful (ok=true) tool result for `state_patch`.
          - After tools are done, reply with a single sentence: "Done."
        SYS
        user_text: ->(workspace) { "workspace_id=#{workspace.id}" },
        assert: lambda { |assistant_text:, workspace:, tools_enabled:, language_policy_enabled:, language_policy_target_lang:, **|
          reasons = []
          unless final_answer_ok?(
            assistant_text,
            language_policy_enabled: language_policy_enabled,
            target_lang: language_policy_target_lang,
          )
            reasons << final_answer_failure_reason(language_policy_enabled: language_policy_enabled, target_lang: language_policy_target_lang)
          end
          reasons << %(draft["foo"] != "bar") if tools_enabled && workspace.draft["foo"] != "bar"
          reasons
        },
      },
      {
        id: "happy_path_parallel",
        title: "Happy path (parallel tool calls: state_get + state_patch -> done)",
        context_overrides: { request_overrides: { parallel_tool_calls: true } },
        prepare: ->(_workspace) { },
        system: <<~SYS.strip,
          You are a tool-using assistant.
          Rules:
          - In your FIRST assistant response, call BOTH tools in a single message:
            1) `state_get`
            2) `state_patch` (set `/draft/foo` to string value "bar")
          - After tools are done, reply with a single sentence: "Done."
        SYS
        user_text: ->(workspace) { "workspace_id=#{workspace.id}" },
        assert: lambda { |assistant_text:, workspace:, tools_enabled:, trace:, language_policy_enabled:, language_policy_target_lang:, **|
          reasons = []
          unless final_answer_ok?(
            assistant_text,
            language_policy_enabled: language_policy_enabled,
            target_lang: language_policy_target_lang,
          )
            reasons << final_answer_failure_reason(language_policy_enabled: language_policy_enabled, target_lang: language_policy_target_lang)
          end
          reasons << %(draft["foo"] != "bar") if tools_enabled && workspace.draft["foo"] != "bar"

          multi =
            Array(trace).any? do |t|
              t.is_a?(Hash) && Array(t[:tool_calls]).size >= 2
            end
          reasons << "expected >=2 tool calls in a single assistant response" if tools_enabled && !multi

          reasons
        },
      },
      {
        id: "long_arguments_guard",
        title: "Long arguments guardrail (ARGUMENTS_TOO_LARGE) + recovery",
        context_overrides: { max_tool_args_bytes: 300, request_overrides: { max_tokens: 256 } },
        prepare: ->(_workspace) { },
        system: <<~SYS.strip,
          You are a tool-using assistant.
          Rules:
          - Always call `state_get` first.
          - IMPORTANT: Call at most ONE tool per assistant message.
          - Then call `state_patch` to set `/draft/foo`.
            - Use request_id "r1".
            - First, try a LONG value (>= 300 'x' characters).
            - If the tool returns ok=false with ARGUMENTS_TOO_LARGE, retry with the short value "bar".
            - If the LONG call unexpectedly succeeds (ok=true), still call `state_patch` again with the short value "bar" so the final state is correct.
          - Do NOT reply "Done." until AFTER you have received a successful (ok=true) tool result for `state_patch` with value "bar".
          - After tools are done, reply with a single sentence: "Done."
        SYS
        user_text: ->(workspace) { "workspace_id=#{workspace.id}" },
        assert: lambda { |assistant_text:, workspace:, tools_enabled:, language_policy_enabled:, language_policy_target_lang:, **|
          reasons = []
          unless final_answer_ok?(
            assistant_text,
            language_policy_enabled: language_policy_enabled,
            target_lang: language_policy_target_lang,
          )
            reasons << final_answer_failure_reason(language_policy_enabled: language_policy_enabled, target_lang: language_policy_target_lang)
          end
          reasons << %(draft["foo"] != "bar") if tools_enabled && workspace.draft["foo"] != "bar"
          reasons
        },
      },
      {
        id: "tool_output_truncation",
        title: "Tool output too large truncation (TOOL_OUTPUT_TOO_LARGE)",
        context_overrides: { max_tool_output_bytes: 5_000, tool_failure_policy: :tolerated },
        prepare: lambda { |workspace|
          workspace.draft["big"] = "x" * 12_000
        },
        system: <<~SYS.strip,
          You are a tool-using assistant.
          Rules:
          - Always call `state_get` first.
          - If the `state_get` tool result returns ok=false with TOOL_OUTPUT_TOO_LARGE, do NOT retry state_get.
            Proceed to call `state_patch` anyway.
          - Then call `state_patch` to set `/draft/foo` to string value "bar".
          - After tools are done, reply with a single sentence: "Done."
        SYS
        user_text: ->(workspace) { "workspace_id=#{workspace.id}" },
        assert: lambda { |assistant_text:, workspace:, tools_enabled:, raw_history:, language_policy_enabled:, language_policy_target_lang:, **|
          reasons = []
          unless final_answer_ok?(
            assistant_text,
            language_policy_enabled: language_policy_enabled,
            target_lang: language_policy_target_lang,
          )
            reasons << final_answer_failure_reason(language_policy_enabled: language_policy_enabled, target_lang: language_policy_target_lang)
          end
          reasons << %(draft["foo"] != "bar") if tools_enabled && workspace.draft["foo"] != "bar"

            saw_truncation =
              Array(raw_history).any? do |m|
                next false unless m.respond_to?(:role) && m.respond_to?(:content)
                next false unless %w[tool tool_result].include?(m.role.to_s)

                m.content.to_s.include?("TOOL_OUTPUT_TOO_LARGE")
              end
            reasons << "expected TOOL_OUTPUT_TOO_LARGE to be emitted at least once" unless saw_truncation

          reasons
        },
      },
      chat_only_scenario,
    ]
  else
    [
      chat_only_scenario,
    ]
  end

default_scenario_ids =
  if tools_enabled
    %w[
      happy_path
      missing_workspace_id
      type_error_recovery
      long_arguments_guard
      chat_only
    ]
  else
    %w[chat_only]
  end

simple_scenario_ids =
  if tools_enabled
    %w[
      happy_path
      chat_only
    ]
  else
    %w[chat_only]
  end

typical_scenario_ids = default_scenario_ids

extreme_scenario_ids =
  if tools_enabled
    %w[
      happy_path
      partial_success_failure
      missing_workspace_id
      type_error_recovery
      long_arguments_guard
      tool_output_truncation
      chat_only
    ]
  else
    %w[chat_only]
  end

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
  ToolCallEval::LanguagePolicy.filter(
    raw_language_policy_filter,
    matrix: language_policy_matrix,
  )

if selected_language_policies.empty?
  warn(
    "No language policy entries selected from OPENROUTER_LANGUAGE_POLICY_FILTER=#{raw_language_policy_filter.inspect}. " \
    "Falling back to off.",
  )
  selected_language_policies = [ToolCallEval::LanguagePolicy::OFF]
end

root = VibeTavernEval::Paths.root
timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
out_dir = root.join("tmp", "llm_tool_call_eval_reports", timestamp)
FileUtils.mkdir_p(out_dir)

reports = []

production_auto_sampling_profile =
  ENV.fetch("OPENROUTER_PRODUCTION_AUTO_SAMPLING_PROFILE", "1") == "1"
recommended_sampling_profiles = OpenRouterSamplingProfiles::CATALOG.filter("recommended")

task_list =
  selected_model_entries.each_with_index.flat_map do |model_entry, model_index|
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
          strategy.id == ToolCallEval::Strategies::PRODUCTION.id &&
          base_profiles.length == 1 &&
          base_profiles.first.id == default_sampling_profile.id
        recommended = recommended_sampling_profiles.find { |p| p.applies_to_model?(model_entry.id) }
        profiles = [recommended] if recommended
      end

      profiles.flat_map do |sampling_profile|
        fallback_profiles.flat_map do |fallback_profile|
          selected_language_policies.map do |language_policy|
            {
              model_entry: model_entry,
              model_index: model_index,
              strategy: strategy,
              fallback_profile: fallback_profile,
              sampling_profile: sampling_profile,
              language_policy: language_policy,
            }
          end
        end
      end
    end
  end

parallel_jobs = [parallel_jobs, task_list.length].min

log_mutex = Mutex.new
log_line =
  lambda do |line|
    log_mutex.synchronize do
      $stderr.puts(line)
      $stderr.flush
    end
  end

sampling_matrix_enabled =
  selected_sampling_profiles.length > 1 ||
    selected_sampling_profiles.any? { |p| p.id != OpenRouterSamplingProfiles::DEFAULT_PROFILE_ID }

language_policy_matrix_enabled = selected_language_policies.length > 1

matrix_enabled =
  fallback_profiles.length > 1 ||
    sampling_matrix_enabled ||
    requested_strategies.length > 1 ||
    language_policy_matrix_enabled

process_task =
  lambda do |task, task_index, task_total|
    model_entry = task.fetch(:model_entry)
    model = model_entry.id
    excluded_workarounds = fallback_matrix ? ["content_tag_tool_call_fallback", "content_tag_fallback"] : []
    model_index = task.fetch(:model_index)
    strategy = task.fetch(:strategy)
    strategy_id = strategy.id.to_s
    apply_model_workarounds = strategy.apply_model_workarounds == true
    apply_infra_defaults = strategy.apply_infra_defaults == true
    apply_provider_defaults = strategy.apply_provider_defaults == true
    model_workaround_presets =
      if apply_model_workarounds
        ToolCallEval::ModelWorkarounds.presets_for(model_entry, exclude: excluded_workarounds)
      else
        []
      end

    fallback_profile = task.fetch(:fallback_profile)
    fallback_profile_id = fallback_profile.fetch(:id).to_s
    enable_tag_fallback = fallback_profile.fetch(:content_tag_tool_call_fallback) == true
    sampling_profile = task.fetch(:sampling_profile)
    sampling_profile_id = sampling_profile.id.to_s

    language_policy = task.fetch(:language_policy)
    language_policy_id = language_policy.id.to_s
    language_policy_enabled = language_policy.enabled == true
    language_policy_target_lang = language_policy.target_lang.to_s
    language_policy_target_lang = nil if language_policy_target_lang.strip.empty?

    llm_options_defaults =
      deep_merge_hashes(
        sampling_profile.llm_options_defaults,
        deep_symbolize_keys(llm_options_defaults_overrides),
      )

    model_idx = model_index + 1
    model_total = selected_model_entries.length
    task_idx = task_index + 1

    client = SimpleInference::Client.new(
      base_url: base_url,
      api_key: api_key,
      headers: headers,
      api_prefix: api_prefix,
      timeout: client_timeout,
      open_timeout: client_open_timeout,
      read_timeout: client_read_timeout,
      adapter: build_http_adapter.call,
    )

    model_label_parts = [model]
    model_label_parts << sampling_profile_id if sampling_matrix_enabled
    model_label_parts << strategy_id if requested_strategies.length > 1
    model_label_parts << fallback_profile_id if fallback_profiles.length > 1
    model_label = matrix_enabled ? model_label_parts.join(":") : model
    safe_model = model_label.gsub(%r{[^a-zA-Z0-9_.-]+}, "__")
    safe_lang = language_policy_id.gsub(%r{[^a-zA-Z0-9_.-]+}, "__")
    provider_tool_calling_preset =
      build_provider_tool_calling_preset.call(
        apply_provider_defaults: apply_provider_defaults,
        enable_tag_fallback: enable_tag_fallback,
      )

    runs = []
    failures = []
    task_effective_tag_fallback = nil

    trials_per_model.times do |trial_idx|
      scenarios.each_with_index do |scenario, scenario_index|
        scenario_idx = scenario_index + 1
        scenario_total = scenarios.length
        scenario_id = scenario.fetch(:id).to_s
        safe_scenario = scenario_id.gsub(%r{[^a-zA-Z0-9_.-]+}, "__")

        log_line.call(
          "[#{task_idx}/#{task_total}] [#{model_idx}/#{model_total}] [#{scenario_idx}/#{scenario_total}] testing #{model_label} lang=#{language_policy_id} scenario=#{scenario_id} (trial #{trial_idx + 1}/#{trials_per_model})...",
        )

        scenario_prepare = scenario[:prepare]
        scenario_user_text = scenario.fetch(:user_text)
        scenario_assert = scenario.fetch(:assert)

        workspace = nil

        effective_request_overrides = deep_merge_hashes(base_request_overrides, {})

        # Default to sequential tool calls for stability unless the request
        # already specifies parallel_tool_calls or a scenario opts in.
        if tools_enabled &&
            !effective_request_overrides.key?(:parallel_tool_calls) &&
            !strategy.default_parallel_tool_calls.nil?
          effective_request_overrides[:parallel_tool_calls] = strategy.default_parallel_tool_calls
        end

        tool_calling =
          merge_tool_calling_configs(
            (apply_infra_defaults ? ToolCallEval::DEFAULT_TOOL_CALLING : {}),
            provider_tool_calling_preset,
            {
              tool_use_mode: tool_use_mode.to_sym,
              tool_failure_policy: tool_failure_policy,
              fallback_retry_count: fallback_retry_count,
              fix_empty_final: fix_empty_final,
              tool_allowlist: tool_allowlist,
              request_overrides: effective_request_overrides,
            },
            *model_workaround_presets,
            scenario[:context_overrides] || {},
          )

        effective_tag_fallback =
          Array(tool_calling[:response_transforms])
            .map { |t| t.to_s.strip }
            .include?("assistant_content_tool_call_tags_to_tool_calls")
        task_effective_tag_fallback = effective_tag_fallback if task_effective_tag_fallback.nil?

        effective_tool_use_mode = normalize_tool_use_mode(tool_calling.fetch(:tool_use_mode, tool_use_mode))
        effective_tools_enabled = effective_tool_use_mode != "disabled"

        system_text = scenario.fetch(:system).to_s
        if language_policy_enabled && language_policy_target_lang
          done_override = localized_done_text(language_policy_target_lang)
          system_text = system_text.gsub("Done.", done_override)
        end

        if language_policy_enabled && language_policy_target_lang
          policy = VibeTavernEval::LanguagePolicyPrompt.build(language_policy_target_lang)
          system_text = [system_text, policy].map(&:to_s).map(&:strip).reject(&:empty?).join("\n\n")
        end

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        retry_attempts_used = 0
        max_attempts = empty_response_retry_count + 1

        ok = true
        error = nil
        error_hint = nil
        error_status = nil
        error_body = nil
        error_raw_body = nil
        assistant_text = nil
        trace = nil
        raw_history = nil

        while retry_attempts_used < max_attempts
          retry_attempts_used += 1

          workspace = ToolCallEval::Workspace.new
          scenario_prepare.call(workspace) if scenario_prepare

          tool_executor = ToolCallEval::Executor.new(workspace: workspace)
          effective_max_tool_args_bytes =
            Integer(
              tool_calling.fetch(:max_tool_args_bytes, AgentCore::Utils::DEFAULT_MAX_TOOL_ARGS_BYTES),
              exception: false,
            ) || AgentCore::Utils::DEFAULT_MAX_TOOL_ARGS_BYTES

          effective_max_tool_output_bytes =
            Integer(
              tool_calling.fetch(:max_tool_output_bytes, AgentCore::Utils::DEFAULT_MAX_TOOL_OUTPUT_BYTES),
              exception: false,
            ) || AgentCore::Utils::DEFAULT_MAX_TOOL_OUTPUT_BYTES

          tools = ToolCallEval.build_tools(executor: tool_executor, max_tool_output_bytes: effective_max_tool_output_bytes)

          tools_registry = AgentCore::Resources::Tools::Registry.new
          tools_registry.register_many(tools)

          exposed_tools = tools.select { |t| t.metadata.fetch(:exposed_to_model, true) == true }

          effective_tool_allowlist = tool_calling.fetch(:tool_allowlist, nil)
          effective_tool_allowlist ||= tool_allowlist
          allowlist_values = normalize_string_list(effective_tool_allowlist)
          if allowlist_values
            exposed_tools = exposed_tools.select { |t| allowlist_values.include?(t.name) }
          end

          prompt_tools = exposed_tools.map(&:to_openai)

          provider =
            VibeTavernEval::AgentCoreOpenAIProvider.new(
              client: client,
              message_transforms: tool_calling.fetch(:message_transforms, nil),
              enable_tool_call_tag_fallback: effective_tag_fallback,
              max_tool_args_bytes: effective_max_tool_args_bytes,
            )

          tool_policy =
            if effective_tools_enabled && allowlist_values
              ToolCallEval::AllowlistPolicy.new(allowlist: allowlist_values)
            end

          runner = ToolCallEval::AgentCoreRunner.new

          request_overrides = tool_calling.fetch(:request_overrides, {})
          run_options = deep_merge_hashes(llm_options_defaults, request_overrides)
          run_options.delete(:model)
          run_options.delete(:messages)
          run_options[:model] = model

          ok = true
          error = nil
          error_status = nil
          error_body = nil
          error_raw_body = nil
          assistant_text = nil
          trace = nil
          raw_history = nil

          begin
            user_text = scenario_user_text.call(workspace).to_s
            if language_policy_enabled && language_policy_target_lang
              done_override = localized_done_text(language_policy_target_lang)
              user_text = user_text.gsub("Done.", done_override)
            end

            prompt_messages = [AgentCore::Message.new(role: :user, content: user_text)]
            prompt =
              AgentCore::PromptBuilder::BuiltPrompt.new(
                system_prompt: system_text,
                messages: prompt_messages,
                tools: effective_tools_enabled ? prompt_tools : [],
                options: run_options,
              )

            trace = []
            current_trace = nil
            current_turn = nil
            last_tool_ok_by_name = {}
            any_tool_success_seen = false

            parse_tool_result =
              lambda do |tool_result|
                text = tool_result.respond_to?(:text) ? tool_result.text.to_s : tool_result.to_s
                envelope =
                  begin
                    JSON.parse(text)
                  rescue JSON::ParserError, TypeError
                    nil
                  end

                ok_value = nil
                codes = []

                if envelope.is_a?(Hash)
                  ok_value = envelope.fetch("ok", nil)
                  codes =
                    Array(envelope.fetch("errors", nil)).filter_map do |err|
                      err.is_a?(Hash) ? err.fetch("code", nil) : nil
                    end
                elsif tool_result.respond_to?(:error?)
                  ok_value = !tool_result.error?
                end

                [ok_value, codes, text.bytesize]
              end

            events = AgentCore::PromptRunner::Events.new

            events.on_turn_start do |turn_num|
              current_turn = turn_num
              current_trace = {
                turn: turn_num,
                request: {
                  model: model,
                  tool_use_mode: effective_tool_use_mode,
                  tool_failure_policy: tool_calling.fetch(:tool_failure_policy, tool_failure_policy).to_s,
                  message_transforms: tool_calling.fetch(:message_transforms, []),
                  response_transforms: tool_calling.fetch(:response_transforms, []),
                },
                response_summary: {},
                tool_calls: [],
                tool_results: [],
              }
              trace << current_trace
            end

            events.on_llm_request do |request_messages, tools|
              next unless current_trace

              current_trace[:request][:messages_count] = request_messages.size
              current_trace[:request][:tools_count] = Array(tools).size

              next if verbose_level <= 0

              tools_on = tools.is_a?(Array) && tools.any?
              msg = "  [#{task_idx}/#{task_total}] [#{model_idx}/#{model_total}] [t#{current_turn}] -> llm (tools=#{tools_on ? "on" : "off"})"
              if verbose_level >= 2
                msg << " msgs=#{request_messages.size}"
                msg << " tools=#{Array(tools).size}"
              end
              log_line.call(msg)
            end

            events.on_llm_response do |response|
              next unless current_trace

              tool_calls = response.respond_to?(:tool_calls) ? response.tool_calls : []
              names =
                Array(tool_calls)
                  .filter_map { |tc| tc.respond_to?(:name) ? tc.name : nil }
                  .map { |n| n.to_s.strip }
                  .reject(&:empty?)
                  .uniq

              summary = {
                has_tool_calls: names.any?,
                tool_calls_count: Array(tool_calls).size,
                ignored_tool_calls_count: 0,
                usage: response.respond_to?(:usage) && response.usage ? response.usage.to_h : nil,
                finish_reason: response.respond_to?(:stop_reason) ? response.stop_reason.to_s : nil,
              }

              assistant_text_raw = response.respond_to?(:message) ? response.message&.text.to_s : ""
              if names.any? && !assistant_text_raw.strip.empty?
                summary[:assistant_content_stripped] = true
                summary[:assistant_content_sample] = assistant_text_raw[0, 200]
              end

              current_trace[:response_summary] = summary

              next if verbose_level <= 0

              msg = "  [#{task_idx}/#{task_total}] [#{model_idx}/#{model_total}] [t#{current_turn}] <- llm"
              msg << " finish=#{summary[:finish_reason]}" if summary[:finish_reason]
              msg << " tool_calls=#{names.join(",")}" if names.any?
              log_line.call(msg)
            end

            events.on_tool_call do |name, arguments, tool_call_id|
              next unless current_trace

              bytes =
                begin
                  JSON.generate(arguments).bytesize
                rescue StandardError
                  arguments.to_s.bytesize
                end

              current_trace[:tool_calls] << {
                id: tool_call_id.to_s,
                name: name.to_s,
                arguments_bytes: bytes,
              }

              next if verbose_level <= 0

              msg = "  [#{task_idx}/#{task_total}] [#{model_idx}/#{model_total}] [t#{current_turn}] -> tool #{name}"
              msg << " args=#{bytes}B" if verbose_level >= 2
              log_line.call(msg)
            end

            events.on_tool_result do |name, result, tool_call_id|
              next unless current_trace

              ok_value, codes, out_bytes = parse_tool_result.call(result)
              ok_value = ok_value == true

              current_trace[:tool_results] << {
                id: tool_call_id.to_s,
                name: name.to_s,
                ok: ok_value,
                error_codes: codes,
              }

              last_tool_ok_by_name[name.to_s] = ok_value
              any_tool_success_seen ||= ok_value

              next if verbose_level <= 0

              msg = "  [#{task_idx}/#{task_total}] [#{model_idx}/#{model_total}] [t#{current_turn}] <- tool #{name} ok=#{ok_value}"
              errors = Array(codes).map(&:to_s).map(&:strip).reject(&:empty?)
              msg << " errors=#{errors.join(",")}" if errors.any?
              msg << " out=#{out_bytes}B" if verbose_level >= 2
              log_line.call(msg)
            end

            tools_registry_for_run = effective_tools_enabled ? tools_registry : nil
            tool_policy_for_run = effective_tools_enabled ? tool_policy : nil

            fix_empty_final = tool_calling.fetch(:fix_empty_final, true) == true
            fix_empty_final_disable_tools = tool_calling.fetch(:fix_empty_final_disable_tools, true) == true

            run_result =
              runner.run(
                prompt: prompt,
                provider: provider,
                tools_registry: tools_registry_for_run,
                tool_policy: tool_policy_for_run,
                max_turns: 12,
                events: events,
                fix_empty_final: fix_empty_final,
                fix_empty_final_disable_tools: fix_empty_final_disable_tools,
                max_tool_output_bytes: effective_max_tool_output_bytes,
              )

            assistant_text = run_result.text
            raw_history = prompt_messages + Array(run_result.messages)

            fail_reasons =
              Array(
                scenario_assert.call(
                  assistant_text: assistant_text,
                  workspace: workspace,
                  tools_enabled: effective_tools_enabled,
                  trace: trace,
                  raw_history: raw_history,
                  language_policy_enabled: language_policy_enabled,
                  language_policy_target_lang: language_policy_target_lang,
                ),
              )

            unless fail_reasons.empty?
              tool_calls_seen =
                effective_tools_enabled &&
                  Array(trace).any? { |t| t.is_a?(Hash) && t.dig(:response_summary, :has_tool_calls) == true }

              if effective_tools_enabled && !tool_calls_seen
                error = "NO_TOOL_CALLS: assistant did not request any tool calls"
              else
                error = "ASSERTION_FAILED: #{fail_reasons.join("; ")}"
              end
              ok = false
            end
          rescue SimpleInference::Errors::HTTPError => e
            ok = false
            error_status = e.status
            error = truncate(e.message, max_chars: 400)
            error_body = e.body.is_a?(Hash) ? e.body : nil
            error_raw_body = truncate(e.raw_body.to_s, max_chars: 20_000)
          rescue SimpleInference::Errors::TimeoutError => e
            ok = false
            error = "TIMEOUT_ERROR: #{truncate(e.message, max_chars: 400)}"
          rescue SimpleInference::Errors::ConnectionError => e
            ok = false
            error = "CONNECTION_ERROR: #{truncate(e.message, max_chars: 400)}"
          rescue SimpleInference::Errors::DecodeError => e
            ok = false
            error = "DECODE_ERROR: #{truncate(e.message, max_chars: 400)}"
          rescue StandardError => e
            ok = false
            error = truncate("#{e.class}: #{e.message}", max_chars: 400)
          end

          failure_category = ok ? nil : error_category(error, status: error_status)
          retryable_empty_response =
            assistant_text.to_s.strip.empty? &&
              error_status.nil? &&
              %w[ASSERTION_FAILED NO_TOOL_CALLS].include?(failure_category)
          retryable_network_error =
            error_status.nil? &&
              %w[CONNECTION_ERROR TIMEOUT_ERROR DECODE_ERROR].include?(failure_category)
          retryable_transient_failure = retryable_empty_response || retryable_network_error

          break unless retryable_transient_failure && retry_attempts_used < max_attempts

          log_line.call(
            "  [#{task_idx}/#{task_total}] [#{model_idx}/#{model_total}] .. transient failure (#{failure_category}); retrying " \
            "(attempt #{retry_attempts_used + 1}/#{max_attempts})",
          )
        end

        if assistant_text.to_s.strip.empty? && error_status.nil?
          category = ok ? nil : error_category(error, status: error_status)
          if ok || %w[ASSERTION_FAILED NO_TOOL_CALLS].include?(category)
            ok = false
            error = "EMPTY_ASSISTANT_TEXT"
          end
        end

        assistant_text_language_shape = nil
        assistant_text_language_ok = nil
        if language_policy_enabled && language_policy_target_lang
          assistant_text_language_shape =
            ToolCallEval::LanguagePolicy.language_shape(
              assistant_text,
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
          model: model_label,
          model_base: model,
          strategy: strategy_id,
          fallback_profile: fallback_profile_id,
          sampling_profile: sampling_profile_id,
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
          llm_options_defaults: llm_options_defaults,
          content_tag_tool_call_fallback: effective_tag_fallback,
          scenario: scenario_id,
          trial: trial_idx + 1,
          ok: ok,
          elapsed_ms: elapsed_ms,
          tool_use_mode: effective_tool_use_mode,
          tools_enabled: effective_tools_enabled,
          context_tool_calling: tool_calling,
          assistant_text: assistant_text,
          assistant_text_language_shape: assistant_text_language_shape,
          assistant_text_language_ok: assistant_text_language_ok,
          draft: workspace.draft,
          error: error,
          error_status: error_status,
          error_body: error_body,
          error_raw_body: error_raw_body,
          error_category: ok ? nil : error_category(error, status: error_status),
          history:
            raw_history&.map do |m|
              if m.respond_to?(:to_serializable_hash)
                m.to_serializable_hash
              else
                { role: m.respond_to?(:role) ? m.role : nil, content: m.respond_to?(:content) ? m.content : m.to_s }
              end
            end,
          trace: trace,
        }

        error_hint = provider_error_hint(report)
        report[:error_hint] = error_hint if error_hint

        file_name = "#{safe_model}__lang_#{safe_lang}__#{safe_scenario}__trial_#{format("%02d", trial_idx + 1)}.json"
        report_path = out_dir.join(file_name)
        File.write(report_path, JSON.pretty_generate(report))

          run_meta = {
            model: model_label,
            model_base: model,
            strategy: strategy_id,
          fallback_profile: fallback_profile_id,
          sampling_profile: sampling_profile_id,
          empty_response_retry_attempts: retry_attempts_used,
          language_policy: language_policy_id,
          assistant_text_language_shape: assistant_text_language_shape,
          assistant_text_language_ok: assistant_text_language_ok,
          content_tag_tool_call_fallback: effective_tag_fallback,
          scenario: scenario_id,
          trial: trial_idx + 1,
          ok: ok,
          elapsed_ms: elapsed_ms,
            error: error,
            error_hint: error_hint,
            error_status: error_status,
            error_category: report[:error_category],
            report_path: report_path.relative_path_from(root).to_s,
          }

        runs << run_meta
        failures << run_meta unless ok

        status_str = ok ? "OK" : "FAIL"
        log_line.call(
          "[#{task_idx}/#{task_total}] [#{model_idx}/#{model_total}] [#{scenario_idx}/#{scenario_total}] #{status_str} #{model_label} lang=#{language_policy_id} scenario=#{scenario_id} (trial #{trial_idx + 1}/#{trials_per_model}, #{elapsed_ms}ms)",
        )
      end
    end

    ok_count = runs.count { |t| t[:ok] }
    rate = ok_count.fdiv(runs.size)
    elapsed = runs.map { |t| t[:elapsed_ms].to_i }.sort
    p50 = elapsed[(elapsed.size * 0.50).floor] || 0
    p95 = elapsed[(elapsed.size * 0.95).floor] || 0

    tool_runs = runs.reject { |t| t[:scenario].to_s == "chat_only" }
    tool_ok_count = tool_runs.count { |t| t[:ok] }
    tool_rate = tool_runs.empty? ? nil : tool_ok_count.fdiv(tool_runs.size)
    tool_elapsed = tool_runs.map { |t| t[:elapsed_ms].to_i }.sort
    tool_p50 = tool_elapsed[(tool_elapsed.size * 0.50).floor] || 0
    tool_p95 = tool_elapsed[(tool_elapsed.size * 0.95).floor] || 0

    control_runs = runs.select { |t| t[:scenario].to_s == "chat_only" }
    control_ok_count = control_runs.count { |t| t[:ok] }
    control_rate = control_runs.empty? ? nil : control_ok_count.fdiv(control_runs.size)
    control_elapsed = control_runs.map { |t| t[:elapsed_ms].to_i }.sort
    control_p50 = control_elapsed[(control_elapsed.size * 0.50).floor] || 0
    control_p95 = control_elapsed[(control_elapsed.size * 0.95).floor] || 0

    failure_samples = failures.first(3)

    lang_ok_runs = nil
    lang_drift_runs = nil
    lang_unknown_runs = nil
    if language_policy_enabled
      lang_ok_runs = runs.count { |t| t[:assistant_text_language_ok] == true }
      lang_drift_runs = runs.count { |t| t[:assistant_text_language_shape].to_s == "drift" }
      lang_unknown_runs = runs.count { |t| t[:assistant_text_language_shape].to_s == "unknown" }
    end

    {
      model: model_label,
      model_base: model,
      strategy: strategy_id,
      fallback_profile: fallback_profile_id,
      sampling_profile: sampling_profile_id,
      language_policy: language_policy_id,
      language_enabled: language_policy_enabled,
      content_tag_tool_call_fallback: task_effective_tag_fallback == true,
      runs: runs.size,
      ok: ok_count,
      ok_rate: rate,
      language_ok_runs: lang_ok_runs,
      language_ok_rate: lang_ok_runs ? lang_ok_runs.fdiv(runs.size) : nil,
      language_drift_runs: lang_drift_runs,
      language_drift_rate: lang_drift_runs ? lang_drift_runs.fdiv(runs.size) : nil,
      language_unknown_runs: lang_unknown_runs,
      language_unknown_rate: lang_unknown_runs ? lang_unknown_runs.fdiv(runs.size) : nil,
      ms_p50: p50,
      ms_p95: p95,
      tool_runs: tool_runs.size,
      tool_ok: tool_ok_count,
      tool_ok_rate: tool_rate,
      tool_ms_p50: tool_p50,
      tool_ms_p95: tool_p95,
      control_runs: control_runs.size,
      control_ok: control_ok_count,
      control_ok_rate: control_rate,
      control_ms_p50: control_p50,
      control_ms_p95: control_p95,
      scenarios: scenarios.map { |s| s[:id] },
      run_results: runs,
      failure_samples: failure_samples,
    }
  end

if parallel_jobs == 1
  reports = task_list.each_with_index.map { |task, task_index| process_task.call(task, task_index, task_list.length) }
else
  queue = Queue.new
  task_list.each_with_index { |task, task_index| queue << [task, task_index] }

  reports_by_index = Array.new(task_list.length)
  worker_errors = Queue.new

  workers =
    Array.new(parallel_jobs) do
      Thread.new do
        loop do
          item =
            begin
              queue.pop(true)
            rescue ThreadError
              break
            end

          task, task_index = item
          reports_by_index[task_index] = process_task.call(task, task_index, task_list.length)
        rescue StandardError => e
          worker_errors << [item, e]
          break
        end
      end
    end

  workers.each(&:join)

  unless worker_errors.empty?
    item, e = worker_errors.pop
    task = item.is_a?(Array) ? item.fetch(0, nil) : nil
    model_entry = task.is_a?(Hash) ? task.fetch(:model_entry, nil) : nil
    model = model_entry.respond_to?(:id) ? model_entry.id : nil
    strategy_id = task.is_a?(Hash) ? task.fetch(:strategy, nil)&.id : nil
    language_policy_id = task.is_a?(Hash) ? task.fetch(:language_policy, nil)&.id : nil
    fallback_profile_id = task.is_a?(Hash) ? task.dig(:fallback_profile, :id) : nil
    sampling_profile_id = task.is_a?(Hash) ? task.fetch(:sampling_profile, nil)&.id : nil
    raise(
      "#{e.class}: worker failed for model=#{model.inspect} strategy=#{strategy_id.inspect} lang=#{language_policy_id.inspect} fallback_profile=#{fallback_profile_id.inspect} sampling_profile=#{sampling_profile_id.inspect}: #{e.message}",
    )
  end

  reports = reports_by_index.compact
end

best_effort_content_tag_tool_call_fallback_models =
  selected_model_entries
    .select { |e| Array(e.workarounds).include?(:content_tag_tool_call_fallback) }
    .map(&:id)

summary = {
  ts: Time.now.utc.iso8601,
  base_url: base_url,
  api_prefix: api_prefix,
  http_adapter: http_adapter_name,
  language_policy_filter: raw_language_policy_filter,
  language_policy_matrix: language_policy_matrix,
  language_policy_strict: language_policy_strict,
  language_policies: selected_language_policies.map(&:id),
  client_timeout: client_timeout,
  client_open_timeout: client_open_timeout,
  client_read_timeout: client_read_timeout,
  fix_empty_final: fix_empty_final,
  tool_use_mode: tool_use_mode,
  tool_failure_policy: tool_failure_policy,
  tool_calling_fallback_retry_count: fallback_retry_count,
  tool_allowlist: tool_allowlist,
  request_overrides: base_request_overrides,
  sampling_profile_filter: sampling_profile_filter,
  sampling_profiles: task_list.map { |t| t[:sampling_profile].id }.uniq,
  sampling_profile_enforce_applicability: enforce_sampling_profile_applicability,
  llm_options_defaults_overrides: llm_options_defaults_overrides,
  model_filter: model_filter,
  selected_models: selected_model_entries.map(&:id),
  strategy_filter: raw_strategy_filter,
  strategy_matrix: strategy_matrix,
  strategies: requested_strategies.map(&:id),
  content_tag_tool_call_fallback_global_override: enable_content_tag_tool_call_fallback,
  best_effort_content_tag_tool_call_fallback_models: best_effort_content_tag_tool_call_fallback_models,
  fallback_matrix: fallback_matrix,
  fallback_profiles: fallback_profiles.map { |p| p.fetch(:id) },
  jobs: parallel_jobs,
  trials_per_model: trials_per_model,
  scenarios: scenarios.map { |s| s[:id] },
  output_dir: out_dir.to_s,
  models: reports,
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
      cat = run[:error_category].to_s
      cat = "unknown" if cat.empty?
      out[sid]["errors"][cat] += 1
    end
  end
summary_by_scenario.each_value { |v| v["errors"] = v["errors"].to_h }
File.write(out_dir.join("summary_by_scenario.json"), JSON.pretty_generate(summary_by_scenario))

summary_by_scenario_and_language_policy =
  all_runs.each_with_object({}) do |run, out|
    lang = run[:language_policy].to_s
    lang = ToolCallEval::LanguagePolicy::OFF.id if lang.empty?
    sid = run[:scenario].to_s

    out[lang] ||= {}
    out[lang][sid] ||= { "runs" => 0, "ok" => 0, "errors" => Hash.new(0) }
    out[lang][sid]["runs"] += 1
    out[lang][sid]["ok"] += 1 if run[:ok] == true
    unless run[:ok] == true
      cat = run[:error_category].to_s
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
    strategy = ToolCallEval::Strategies::PRODUCTION.id if strategy.empty?
    sid = run[:scenario].to_s

    out[strategy] ||= {}
    out[strategy][sid] ||= { "runs" => 0, "ok" => 0, "errors" => Hash.new(0) }
    out[strategy][sid]["runs"] += 1
    out[strategy][sid]["ok"] += 1 if run[:ok] == true
    unless run[:ok] == true
      cat = run[:error_category].to_s
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

successes = reports.sum { |r| r[:ok].to_i }
total_runs = reports.sum { |r| r[:runs].to_i }
failures = total_runs - successes

tool_runs = all_runs.reject { |r| r[:scenario].to_s == "chat_only" }
tool_ok = tool_runs.count { |r| r[:ok] == true }
control_runs = all_runs.select { |r| r[:scenario].to_s == "chat_only" }
control_ok = control_runs.count { |r| r[:ok] == true }

puts "LLM Tool Call Eval"
puts "ts: #{summary[:ts]}"
puts "base_url: #{base_url}"
puts "api_prefix: #{api_prefix}"
puts "http_adapter: #{http_adapter_name}"
puts "client_timeout: #{client_timeout || "(none)"}"
puts "client_open_timeout: #{client_open_timeout || "(none)"}"
puts "client_read_timeout: #{client_read_timeout || "(none)"}"
puts "tool_use_mode: #{tool_use_mode}"
puts "tool_failure_policy: #{tool_failure_policy}"
puts "tool_calling_fallback_retry_count: #{fallback_retry_count}"
puts "fix_empty_final: #{fix_empty_final}"
puts "tool_allowlist: #{tool_allowlist ? tool_allowlist.join(",") : "(full)"}"
puts "request_overrides: #{base_request_overrides.any? ? base_request_overrides.keys.join(",") : "(none)"}"
puts "sampling_profile_filter: #{sampling_profile_filter}"
puts "sampling_profiles: #{task_list.map { |t| t[:sampling_profile].id }.uniq.join(",")}"
puts "model_filter: #{model_filter}"
puts "selected_models: #{selected_model_entries.map(&:id).join(",")}"
puts "strategy_filter: #{raw_strategy_filter}" unless raw_strategy_filter.empty?
puts "strategy_matrix: #{strategy_matrix}" if strategy_matrix
puts "strategies: #{requested_strategies.map(&:id).join(",")}"
puts "language_policy_filter: #{raw_language_policy_filter}" unless raw_language_policy_filter.strip.empty?
puts "language_policy_matrix: #{language_policy_matrix}" if language_policy_matrix
puts "language_policy_strict: #{language_policy_strict}" if language_policy_strict
puts "language_policies: #{selected_language_policies.map(&:id).join(",")}"
puts "parallel_tool_calls(default): #{base_request_overrides.fetch(:parallel_tool_calls, "(provider default)")}"
puts "content_tag_tool_call_fallback_global_override: #{enable_content_tag_tool_call_fallback}"
if best_effort_content_tag_tool_call_fallback_models.any?
  puts "best_effort_content_tag_tool_call_fallback_models: #{best_effort_content_tag_tool_call_fallback_models.join(",")}"
end
puts "fallback_matrix: #{fallback_matrix} (profiles=#{fallback_profiles.map { |p| p.fetch(:id) }.join(",")})"
puts "jobs: #{parallel_jobs}"
puts "trials_per_model: #{trials_per_model}"
puts "scenarios: #{scenarios.map { |s| s[:id] }.join(",")}"
puts "model_profiles: #{reports.size} (runs=#{total_runs}, ok=#{successes}, fail=#{failures})"
puts "tool_scenarios_only: #{tool_ok}/#{tool_runs.size}" if tool_runs.any?
puts "control_chat_only: #{control_ok}/#{control_runs.size}" if control_runs.any?
puts "full report: #{out_dir.relative_path_from(root)}"
puts

header = [
  "model",
  "profile",
  "strategy",
  "lang",
  "fallback_profile",
  "tool_ok",
  "tool_rate",
  "control_ok",
  "control_rate",
  "tool_p95_ms",
  "status",
  "category",
  "sample",
  "error",
]
rows =
  reports.map do |r|
    sample = Array(r[:failure_samples]).first
    sample_path = sample ? sample[:report_path].to_s : "-"
    err = sample ? truncate(sample[:error_hint] || sample[:error].to_s, max_chars: 120) : "-"
    [
      r[:model_base].to_s,
      r[:sampling_profile].to_s,
      r[:strategy].to_s,
      r[:language_policy].to_s,
      r[:fallback_profile].to_s,
      "#{r[:tool_ok]}/#{r[:tool_runs]}",
      r[:tool_ok_rate] ? format("%.0f%%", r[:tool_ok_rate].to_f * 100) : "-",
      "#{r[:control_ok]}/#{r[:control_runs]}",
      r[:control_ok_rate] ? format("%.0f%%", r[:control_ok_rate].to_f * 100) : "-",
      r[:tool_ms_p95].to_s,
      sample && sample[:error_status] ? sample[:error_status].to_s : "-",
      sample ? (sample[:error_category] || "-") : "-",
      sample_path,
      err,
    ]
  end

widths = header.map.with_index { |h, idx| ([h.length] + rows.map { |row| row[idx].length }).max }

fmt = widths.map { |w| "%-#{w}s" }.join(" | ")
sep = widths.map { |w| "-" * w }.join("-|-")

puts format(fmt, *header)
puts sep
rows.each { |row| puts format(fmt, *row) }
