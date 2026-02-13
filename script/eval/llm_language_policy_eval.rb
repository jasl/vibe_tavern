#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "thread"
require "time"

require_relative "support/openrouter_sampling_profiles"
require_relative "support/openrouter_models"
require_relative "support/capabilities_registry"

# Default settings
ENV["RAILS_ENV"] ||= "development"

# Load Rails environment (for SimpleInference + VibeTavern pipeline)
require_relative "../../config/environment"

module LanguagePolicyEval
  class ModelCatalog
    Entry = Struct.new(:id, :tags, keyword_init: true) do
      def initialize(id:, tags: [])
        super(
          id: id.to_s,
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

    def self.build(&block)
      builder = Builder.new
      builder.instance_eval(&block) if block
      builder.to_catalog
    end

    def initialize(entries)
      @entries = Array(entries).compact
    end

    def ids
      @entries.map(&:id)
    end

    def filter(raw_filter)
      tokens = raw_filter.to_s.split(",").map(&:strip).reject(&:empty?)
      return @entries.dup if tokens.empty?
      return @entries.dup if tokens.any? { |token| %w[all full *].include?(token.downcase) }

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

    class Builder
      def initialize
        @entries = []
      end

      def model(id, tags: [])
        @entries << Entry.new(id: id, tags: tags)
      end

      def to_catalog
        ModelCatalog.new(@entries)
      end
    end
  end

  module LanguagePolicy
    Entry = Struct.new(:id, :enabled, :target_lang, :target_lang_raw, keyword_init: true) do
      def initialize(id:, enabled:, target_lang: nil, target_lang_raw: nil)
        super(
          id: id.to_s,
          enabled: enabled == true,
          target_lang: target_lang&.to_s,
          target_lang_raw: target_lang_raw&.to_s,
        )
      end
    end

    DEFAULT_TARGET_LANGS = %w[zh-CN ja-JP].freeze

    OFF =
      Entry.new(
        id: "off",
        enabled: false,
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
      "ja" => "ja-JP",
      "ja-jp" => "ja-JP",
      "ko" => "ko-KR",
      "ko-kr" => "ko-KR",
      "yue" => "yue-HK",
      "yue-hk" => "yue-HK",
    }.freeze

    TAG_FORMS = {
      "en-US" => %w[en-US en-us en],
      "zh-CN" => %w[zh-CN zh-cn zh-Hans zh-hans],
      "zh-TW" => %w[zh-TW zh-tw zh-Hant zh-hant],
      "ja-JP" => %w[ja-JP ja-jp ja],
      "ko-KR" => %w[ko-KR ko-kr ko],
      "yue-HK" => %w[yue-HK yue-hk yue],
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
            canonical.empty? ? nil : entry_for(canonical, raw: token)
          end
        end

      entries = Array(entries).flatten.compact
      entries = entries.uniq { |e| e.id }
      entries = [OFF] if entries.empty?

      entries.reject { |entry| exclude_tokens.any? { |token| token.to_s.strip.downcase == entry.id.downcase } }
    end

    def expand_tag_forms(entries, enabled:)
      return Array(entries) unless enabled

      Array(entries).flat_map do |entry|
        next entry unless entry.enabled && entry.target_lang

        canonical = canonical_target_lang(entry.target_lang)
        forms = TAG_FORMS.fetch(canonical, [canonical])
        forms.map do |raw|
          Entry.new(
            id: "#{canonical}@#{raw}",
            enabled: true,
            target_lang: canonical,
            target_lang_raw: raw,
          )
        end
      end
    end

    def strip_language_spans(text)
      text.to_s.gsub(/<\s*lang\b[^>]*>.*?<\/\s*lang\s*>/im, "")
    rescue StandardError
      text.to_s
    end

    def strip_verbatim_zones(text)
      s = text.to_s.dup
      s.gsub!(/```.*?```/m, " ")
      s.gsub!(/`[^`]*`/, " ")
      s.gsub!(/{{.*?}}/m, " ")
      s.gsub!(/{%.*?%}/m, " ")
      s.gsub!(/\[[^\]]+\]\((https?:\/\/[^\)]+)\)/i, " ")
      s.gsub!(/https?:\/\/\S+/i, " ")
      s.gsub!(/<[^>]+>/, " ")
      s
    rescue StandardError
      text.to_s
    end

    def language_shape(text, target_lang:)
      t = strip_verbatim_zones(strip_language_spans(text))
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

    def entry_for(target_lang, raw:)
      canonical = canonical_target_lang(target_lang)
      Entry.new(id: canonical, enabled: true, target_lang: canonical, target_lang_raw: raw)
    end
    private_class_method :entry_for

    def matrix_entries(langs)
      [OFF] + Array(langs).map { |lang| entry_for(lang, raw: lang) }
    end
    private_class_method :matrix_entries
  end

  module Util
    module_function

    def safe_filename(value)
      value.to_s.gsub(%r{[^a-zA-Z0-9_.-]+}, "__")
    end

    def extract_injected_target_lang(messages)
      system_text =
        Array(messages).filter_map do |m|
          next unless m.is_a?(Hash)

          role = m[:role].to_s
          next unless role == "system"

          content = m[:content].to_s
          content.include?("Language Policy:") ? content : nil
        end.first

      return nil unless system_text

      system_text[/Respond in:\s*([A-Za-z0-9-]+)/, 1]
    rescue StandardError
      nil
    end

    def parse_lang_spans(text)
      spans = []
      raw = text.to_s
      raw.scan(/<lang\b([^>]*)>(.*?)<\/lang>/im) do |attrs, inner|
        attrs_str = attrs.to_s
        code =
          attrs_str[/\bcode\s*=\s*["']([^"']+)["']/i, 1] ||
            attrs_str[/\bcode\s*=\s*([^\s>]+)/i, 1]
        spans << { code: code.to_s, inner: inner.to_s }
      end
      spans
    rescue StandardError
      []
    end
  end
end

api_key = ENV.fetch("OPENROUTER_API_KEY", "").to_s.strip
if api_key.empty?
  warn "Missing OPENROUTER_API_KEY."
  exit 2
end

base_url = ENV.fetch("OPENROUTER_BASE_URL", "https://openrouter.ai/api").to_s
api_prefix = ENV.fetch("OPENROUTER_API_PREFIX", "/v1").to_s

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

headers = {}
headers["HTTP-Referer"] = ENV["OPENROUTER_HTTP_REFERER"] if ENV["OPENROUTER_HTTP_REFERER"]
headers["X-Title"] = ENV["OPENROUTER_X_TITLE"] if ENV["OPENROUTER_X_TITLE"]

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

max_tokens =
  begin
    Integer(ENV.fetch("OPENROUTER_MAX_TOKENS", "350"))
  rescue ArgumentError, TypeError
    350
  end
max_tokens = 1 if max_tokens < 1

language_policy_strict = ENV.fetch("OPENROUTER_LANGUAGE_POLICY_STRICT", "0") == "1"
language_policy_matrix = ENV.fetch("OPENROUTER_LANGUAGE_POLICY_MATRIX", "0") == "1"
raw_language_policy_filter = ENV.fetch("OPENROUTER_LANGUAGE_POLICY_FILTER", "").to_s
tag_forms_matrix = ENV.fetch("OPENROUTER_LANGUAGE_TAG_FORMS_MATRIX", "0") == "1"

selected_language_policies =
  LanguagePolicyEval::LanguagePolicy.filter(
    raw_language_policy_filter,
    matrix: language_policy_matrix,
  )

if selected_language_policies.empty?
  warn(
    "No language policy entries selected from OPENROUTER_LANGUAGE_POLICY_FILTER=#{raw_language_policy_filter.inspect}. " \
    "Falling back to off.",
  )
  selected_language_policies = [LanguagePolicyEval::LanguagePolicy::OFF]
end

selected_language_policies =
  LanguagePolicyEval::LanguagePolicy.expand_tag_forms(
    selected_language_policies,
    enabled: tag_forms_matrix,
  )

MODEL_CATALOG =
  LanguagePolicyEval::ModelCatalog.build do
    VibeTavernEval::OpenRouterModels.entries.each do |entry|
      model entry.id, tags: entry.tags
    end
  end

model_filter = ENV.fetch("OPENROUTER_MODEL_FILTER", "stable").to_s
selected_models = MODEL_CATALOG.filter(model_filter)

if selected_models.empty?
  warn "No models matched OPENROUTER_MODEL_FILTER=#{model_filter.inspect}."
  warn "Available model ids: #{MODEL_CATALOG.ids.join(", ")}"
  exit 2
end

sampling_profile_filter =
  ENV.fetch("OPENROUTER_SAMPLING_PROFILE_FILTER", OpenRouterSamplingProfiles::DEFAULT_PROFILE_ID).to_s
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
    id: "verbatim_zones",
    title: "Verbatim zones (code/macros/URL) preserved",
    uses_lang_spans: false,
    user_text: lambda do |lang|
      label = lang.to_s.strip
      language_hint = label.empty? ? "English" : "the target language"

      <<~TEXT
        Reply with 2 short sentences in #{language_hint}.

        Include the following EXACTLY (verbatim) somewhere in your reply:

        1) Code block:
        ```ruby
        puts "Hello, {{char}}"
        ```

        2) Liquid macro: {{char}}
        3) Liquid tag: {% if x %}OK{% endif %}
        4) URL: https://example.com/DO_NOT_TRANSLATE_001
      TEXT
    end,
    assert: lambda do |assistant_text:, **|
      reasons = []
      reasons << "missing code snippet" unless assistant_text.to_s.include?("puts \"Hello, {{char}}\"")
      reasons << "missing macro {{char}}" unless assistant_text.to_s.include?("{{char}}")
      reasons << "missing Liquid tag" unless assistant_text.to_s.include?("{% if x %}OK{% endif %}")
      reasons << "missing URL" unless assistant_text.to_s.include?("https://example.com/DO_NOT_TRANSLATE_001")
      reasons
    end,
  },
  {
    id: "zh_idioms",
    title: "zh-CN vs zh-TW localized word choice",
    uses_lang_spans: false,
    user_text: lambda do |lang|
      canonical = LanguagePolicyEval::LanguagePolicy.canonical_target_lang(lang)
      return "Skip." unless %w[zh-CN zh-TW].include?(canonical)

      word = canonical == "zh-TW" ? "道地" : "地道"
      other = canonical == "zh-TW" ? "地道" : "道地"

      <<~TEXT
        Write one short sentence meaning "This restaurant is authentic."
        Requirements:
        - MUST include the exact word: #{word}
        - MUST NOT include: #{other}
      TEXT
    end,
    assert: lambda do |assistant_text:, language_policy_target_lang:, **|
      canonical = LanguagePolicyEval::LanguagePolicy.canonical_target_lang(language_policy_target_lang)
      return [] unless %w[zh-CN zh-TW].include?(canonical)

      expected = canonical == "zh-TW" ? "道地" : "地道"
      forbidden = canonical == "zh-TW" ? "地道" : "道地"

      reasons = []
      reasons << "missing #{expected}" unless assistant_text.to_s.include?(expected)
      reasons << "contains forbidden #{forbidden}" if assistant_text.to_s.include?(forbidden)
      reasons
    end,
  },
  {
    id: "roleplay_lang_span",
    title: "Mixed-language roleplay span (<lang code=...>)",
    uses_lang_spans: true,
    user_text: lambda do |lang|
      canonical = LanguagePolicyEval::LanguagePolicy.canonical_target_lang(lang)
      return "Skip." unless %w[zh-CN zh-TW].include?(canonical)

      translation = canonical == "zh-TW" ? "謝謝" : "谢谢"
      line2 = canonical == "zh-TW" ? "我：我聽不懂你在說什麼" : "我：我听不懂你在说什么"

      <<~TEXT
        Write EXACTLY 2 lines of roleplay dialogue.
        Requirements:
        - Line 1 MUST start with: 太君：
        - In line 1, include this exact Japanese quote wrapped in a lang span: <lang code="ja">ありがとう</lang>
        - Immediately after </lang>, add parentheses with the translation in the main language: （#{translation}）
        - Line 2 MUST be exactly: #{line2}
      TEXT
    end,
    assert: lambda do |assistant_text:, language_policy_target_lang:, **|
      canonical = LanguagePolicyEval::LanguagePolicy.canonical_target_lang(language_policy_target_lang)
      return [] unless %w[zh-CN zh-TW].include?(canonical)

      translation = canonical == "zh-TW" ? "謝謝" : "谢谢"
      line2 = canonical == "zh-TW" ? "我：我聽不懂你在說什麼" : "我：我听不懂你在说什么"

      reasons = []
      text = assistant_text.to_s
      reasons << "expected <lang> span" unless text.match?(/<lang\b[^>]*>.*?<\/lang>/im)
      reasons << "expected Japanese quote ありがとう" unless text.include?("ありがとう")
      reasons << "expected translation (#{translation})" unless text.include?("（#{translation}）")
      reasons << "expected line 2 exact" unless text.lines.map(&:chomp).include?(line2)

      spans = LanguagePolicyEval::Util.parse_lang_spans(text)
      span = spans.first
      span_code = span ? LanguagePolicyEval::LanguagePolicy.canonical_target_lang(span[:code]) : nil
      inner_shape =
        span ? LanguagePolicyEval::LanguagePolicy.language_shape(span[:inner], target_lang: span_code) : nil

      reasons << "expected lang span code to be ja/ja-JP" unless span_code == "ja-JP"
      reasons << "expected Japanese content inside <lang> span" unless inner_shape == "ok"
      reasons
    end,
  },
].freeze

default_scenario_ids = %w[verbatim_zones zh_idioms roleplay_lang_span]
simple_scenario_ids = %w[verbatim_zones roleplay_lang_span]

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
out_dir = Rails.root.join("tmp", "llm_language_policy_eval_reports", timestamp)
FileUtils.mkdir_p(out_dir)

task_list =
  selected_models.flat_map do |model_entry|
    selected_sampling_profiles.flat_map do |sampling_profile|
      selected_language_policies.flat_map do |language_policy|
        scenarios.map do |scenario|
          {
            model: model_entry.id,
            sampling_profile: sampling_profile,
            language_policy: language_policy,
            scenario: scenario,
          }
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

process_task =
  lambda do |task, task_index, task_total|
    model = task.fetch(:model)
    sampling_profile = task.fetch(:sampling_profile)
    sampling_profile_id = sampling_profile.id.to_s
    language_policy = task.fetch(:language_policy)
    scenario = task.fetch(:scenario)

    language_policy_id = language_policy.id.to_s
    language_policy_enabled = language_policy.enabled == true
    language_policy_target_lang = language_policy.target_lang.to_s
    language_policy_target_lang = nil if language_policy_target_lang.strip.empty?
    target_lang_raw =
      if language_policy.target_lang_raw.to_s.strip.empty?
        language_policy_target_lang
      else
        language_policy.target_lang_raw.to_s
      end

    scenario_id = scenario.fetch(:id).to_s

    llm_options_defaults = sampling_profile.llm_options_defaults
    llm_options_defaults = llm_options_defaults.merge(max_tokens: max_tokens)

    safe_model = LanguagePolicyEval::Util.safe_filename(model)
    safe_profile = LanguagePolicyEval::Util.safe_filename(sampling_profile_id)
    safe_lang = LanguagePolicyEval::Util.safe_filename(language_policy_id)
    safe_scenario = LanguagePolicyEval::Util.safe_filename(scenario_id)

    reports = []

    trials_per_model.times do |trial_idx|
      task_idx = task_index + 1
      log_line.call(
        "[#{task_idx}/#{task_total}] testing #{model} profile=#{sampling_profile_id} lang=#{language_policy_id} scenario=#{scenario_id} (trial #{trial_idx + 1}/#{trials_per_model})...",
      )

      client =
        SimpleInference::Client.new(
          base_url: base_url,
          api_key: api_key,
          headers: headers,
          api_prefix: api_prefix,
          timeout: client_timeout,
          open_timeout: client_open_timeout,
          read_timeout: client_read_timeout,
        )

      context = nil
      if language_policy_enabled && target_lang_raw
        lp_cfg = {
          enabled: true,
          target_lang: target_lang_raw,
        }
        lp_cfg[:special_tags] = ["lang"] if scenario[:uses_lang_spans] == true
        context = { language_policy: lp_cfg }
      end

      runner_config =
        TavernKit::VibeTavern::RunnerConfig.build(
          provider: "openrouter",
          model: model,
          context: context,
          llm_options_defaults: llm_options_defaults,
          capabilities_overrides: VibeTavernEval::CapabilitiesRegistry.lookup(provider_id: "openrouter", model: model),
        )

      prompt_runner = TavernKit::VibeTavern::PromptRunner.new(client: client)

      user_text = scenario.fetch(:user_text).call(language_policy_target_lang || "")
      history = [TavernKit::PromptBuilder::Message.new(role: :user, content: user_text)]

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      retry_attempts_used = 0
      max_attempts = empty_response_retry_count + 1
      ok = true
      error = nil
      assistant_text = nil
      assistant_message = nil
      finish_reason = nil
      injected_target_lang = nil

      begin
        prompt_request =
          prompt_runner.build_request(
            runner_config: runner_config,
            history: history,
            strict: false,
          )
        injected_target_lang = LanguagePolicyEval::Util.extract_injected_target_lang(prompt_request.messages)

        transient_error = nil

        while retry_attempts_used < max_attempts
          retry_attempts_used += 1

          begin
            result = prompt_runner.perform(prompt_request)
            assistant_message = result.assistant_message
            finish_reason = result.finish_reason
            assistant_text = assistant_message.fetch("content", nil).to_s
            transient_error = nil
          rescue SimpleInference::Errors::TimeoutError => e
            transient_error = "TIMEOUT_ERROR: #{e.message}"
          rescue SimpleInference::Errors::ConnectionError => e
            transient_error = "CONNECTION_ERROR: #{e.message}"
          rescue SimpleInference::Errors::DecodeError => e
            transient_error = "DECODE_ERROR: #{e.message}"
          end

          if transient_error
            break if retry_attempts_used >= max_attempts

            log_line.call(
              "  [#{task_idx}/#{task_total}] .. transient failure (#{transient_error.split(":", 2).first}); retrying " \
              "(attempt #{retry_attempts_used + 1}/#{max_attempts})",
            )
            next
          end

          break unless assistant_text.strip.empty? && retry_attempts_used < max_attempts

          log_line.call(
            "  [#{task_idx}/#{task_total}] .. empty assistant_text; retrying (attempt #{retry_attempts_used + 1}/#{max_attempts})",
          )
        end

        if transient_error
          ok = false
          error = transient_error
        elsif assistant_text.strip.empty?
          ok = false
          error = "EMPTY_ASSISTANT_TEXT"
        else
          reasons =
            Array(
              scenario.fetch(:assert).call(
                assistant_text: assistant_text,
                language_policy_enabled: language_policy_enabled,
                language_policy_target_lang: language_policy_target_lang,
                injected_target_lang: injected_target_lang,
              ),
            )

          unless reasons.empty?
            ok = false
            error = "ASSERTION_FAILED: #{reasons.join("; ")}"
          end
        end
      rescue SimpleInference::Errors::HTTPError => e
        ok = false
        error = "HTTP_ERROR: #{e.status} #{e.message}"
      rescue StandardError => e
        ok = false
        error = "#{e.class}: #{e.message}"
      end

      assistant_text_language_shape = nil
      assistant_text_language_ok = nil
      if language_policy_enabled && language_policy_target_lang
        assistant_text_language_shape =
          LanguagePolicyEval::LanguagePolicy.language_shape(
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
        model: model,
        sampling_profile: sampling_profile_id,
        empty_response_retry: {
          max_retries: empty_response_retry_count,
          attempts: retry_attempts_used,
        },
        language_policy: {
          id: language_policy_id,
          enabled: language_policy_enabled,
          target_lang: language_policy_target_lang,
          target_lang_raw: target_lang_raw,
          injected_target_lang: injected_target_lang,
          strict: language_policy_strict,
        },
        scenario: scenario_id,
        trial: trial_idx + 1,
        ok: ok,
        error: error,
        elapsed_ms: elapsed_ms,
        finish_reason: finish_reason,
        assistant_text: assistant_text,
        assistant_message: assistant_message,
        assistant_text_language_shape: assistant_text_language_shape,
        assistant_text_language_ok: assistant_text_language_ok,
      }

      file_name = "#{safe_model}__#{safe_profile}__lang_#{safe_lang}__#{safe_scenario}__trial_#{format("%02d", trial_idx + 1)}.json"
      report_path = out_dir.join(file_name)
      File.write(report_path, JSON.pretty_generate(report))
      report[:report_path] = report_path.relative_path_from(Rails.root).to_s

      reports << report
    end

    reports
  end

reports =
  if parallel_jobs == 1
    task_list.each_with_index.flat_map { |task, idx| process_task.call(task, idx, task_list.length) }
  else
    queue = Queue.new
    task_list.each_with_index { |task, idx| queue << [task, idx] }

    worker_errors = Queue.new
    reports_by_index = Array.new(task_list.length)

    workers =
      Array.new(parallel_jobs) do
        Thread.new do
          loop do
            task, idx =
              begin
                queue.pop(true)
              rescue ThreadError
                break
              end

            reports_by_index[idx] = process_task.call(task, idx, task_list.length)
          rescue StandardError => e
            worker_errors << [task, e]
            break
          end
        end
      end

    workers.each(&:join)

    unless worker_errors.empty?
      task, e = worker_errors.pop
      model = task.is_a?(Hash) ? task.fetch(:model, nil) : nil
      scenario = task.is_a?(Hash) ? task.dig(:scenario, :id) : nil
      raise "#{e.class}: worker failed for model=#{model.inspect} scenario=#{scenario.inspect}: #{e.message}"
    end

    reports_by_index.compact.flatten(1)
  end

summary = {
  ts: Time.now.utc.iso8601,
  base_url: base_url,
  api_prefix: api_prefix,
  client_timeout: client_timeout,
  client_open_timeout: client_open_timeout,
  client_read_timeout: client_read_timeout,
  max_tokens: max_tokens,
  model_filter: model_filter,
  selected_models: selected_models.map(&:id),
  sampling_profile_filter: sampling_profile_filter,
  sampling_profiles: selected_sampling_profiles.map(&:id),
  language_policy_filter: raw_language_policy_filter,
  language_policy_matrix: language_policy_matrix,
  language_policy_strict: language_policy_strict,
  language_tag_forms_matrix: tag_forms_matrix,
  language_policies: selected_language_policies.map(&:id),
  trials_per_model: trials_per_model,
  jobs: parallel_jobs,
  scenarios: scenarios.map { |s| s[:id] },
  output_dir: out_dir.to_s,
}

File.write(out_dir.join("summary.json"), JSON.pretty_generate(summary))
File.write(out_dir.join("runs.jsonl"), reports.map { |r| JSON.generate(r) }.join("\n") + "\n")

summary_by_scenario_and_language_policy =
  reports.each_with_object({}) do |run, out|
    sid = run.fetch(:scenario).to_s
    lang = run.dig(:language_policy, :id).to_s
    lang = LanguagePolicyEval::LanguagePolicy::OFF.id if lang.empty?

    out[lang] ||= {}
    out[lang][sid] ||= { "runs" => 0, "ok" => 0, "errors" => Hash.new(0) }
    out[lang][sid]["runs"] += 1
    out[lang][sid]["ok"] += 1 if run[:ok] == true
    unless run[:ok] == true
      err = run[:error].to_s
      cat =
        if err.start_with?("LANGUAGE_DRIFT:")
          "LANGUAGE_DRIFT"
        elsif err.start_with?("EMPTY_ASSISTANT_TEXT")
          "EMPTY_ASSISTANT_TEXT"
        elsif err.start_with?("CONNECTION_ERROR:")
          "CONNECTION_ERROR"
        elsif err.start_with?("TIMEOUT_ERROR:")
          "TIMEOUT_ERROR"
        elsif err.start_with?("DECODE_ERROR:")
          "DECODE_ERROR"
        elsif err.start_with?("ASSERTION_FAILED:")
          "ASSERTION_FAILED"
        elsif err.start_with?("HTTP_ERROR:")
          "HTTP_ERROR"
        else
          "EXCEPTION"
        end
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

successes = reports.count { |r| r[:ok] == true }
failures = reports.length - successes

puts "LLM Language Policy Eval"
puts "ts: #{summary[:ts]}"
puts "base_url: #{base_url}"
puts "api_prefix: #{api_prefix}"
puts "model_filter: #{model_filter}"
puts "selected_models: #{selected_models.map(&:id).join(",")}"
puts "sampling_profiles: #{selected_sampling_profiles.map(&:id).join(",")}"
puts "language_policy_filter: #{raw_language_policy_filter}" unless raw_language_policy_filter.strip.empty?
puts "language_policy_matrix: #{language_policy_matrix}" if language_policy_matrix
puts "language_tag_forms_matrix: #{tag_forms_matrix}" if tag_forms_matrix
puts "language_policy_strict: #{language_policy_strict}" if language_policy_strict
puts "language_policies: #{selected_language_policies.map(&:id).join(",")}"
puts "trials_per_model: #{trials_per_model}"
puts "scenarios: #{scenarios.map { |s| s[:id] }.join(",")}"
puts "runs: #{reports.length} (ok=#{successes}, fail=#{failures})"
puts "full report: #{out_dir.relative_path_from(Rails.root)}"
puts

header = ["model", "profile", "lang", "scenario", "runs", "ok", "rate", "sample"]
rows =
  reports
    .group_by { |r| [r[:model].to_s, r[:sampling_profile].to_s, r.dig(:language_policy, :id).to_s, r[:scenario].to_s] }
    .map do |(model, profile, lang, scenario_id), runs|
      ok_count = runs.count { |r| r[:ok] == true }
      sample = runs.find { |r| r[:ok] != true } || runs.first
      sample_path = sample ? sample[:report_path].to_s : "-"
      [
        model,
        profile,
        lang,
        scenario_id,
        runs.length.to_s,
        ok_count.to_s,
        format("%.0f%%", ok_count.fdiv(runs.length) * 100),
        sample_path,
      ]
    end
    .sort_by { |row| row[0] }

widths = header.map.with_index { |h, idx| ([h.length] + rows.map { |row| row[idx].length }).max }
fmt = widths.map { |w| "%-#{w}s" }.join(" | ")
sep = widths.map { |w| "-" * w }.join("-|-")

puts format(fmt, *header)
puts sep
rows.each { |row| puts format(fmt, *row) }
