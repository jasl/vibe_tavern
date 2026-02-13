# frozen_string_literal: true

# LLM configuration seeds (providers/models/presets).
#
# Notes:
# - Do not require `script/*` here. Seeds intentionally duplicate the small
#   "recommended sampling" catalog to keep app boot minimal and deterministic.

module DbSeeds
  module LLM
    OPENROUTER_MODELS = [
      "deepseek/deepseek-v3.2:nitro",
      "deepseek/deepseek-chat-v3-0324:nitro",
      "x-ai/grok-4.1-fast",
      "google/gemini-2.5-flash:nitro",
      "google/gemini-3-flash-preview:nitro",
      "google/gemini-3-pro-preview:nitro",
      "anthropic/claude-opus-4.6:nitro",
      "openai/gpt-5.2-chat:nitro",
      "openai/gpt-5.2:nitro",
      "minimax/minimax-m2-her",
      "minimax/minimax-m2.5:nitro",
      "qwen/qwen3-30b-a3b-instruct-2507:nitro",
      "qwen/qwen3-next-80b-a3b-instruct:nitro",
      "qwen/qwen3-235b-a22b-2507:nitro",
      "z-ai/glm-5:nitro",
      "z-ai/glm-4.7-flash:nitro",
      "moonshotai/kimi-k2.5:nitro",
    ].freeze

    # "Production recommended" sampling params used by the eval harness when
    # OPENROUTER_PRODUCTION_AUTO_SAMPLING_PROFILE=1 and only the "default" profile
    # is requested.
    RECOMMENDED_SAMPLING = [
      {
        id: "deepseek_v3_2_local_recommended",
        applies_to: ["deepseek/deepseek-v3.2*"],
        llm_options_overrides: { temperature: 1.0, top_p: 0.95 },
      },
      {
        id: "grok_default",
        applies_to: ["x-ai/grok-*"],
        llm_options_overrides: { temperature: 0.3 },
      },
      {
        id: "qwen_recommended",
        applies_to: ["qwen/qwen3-*"],
        llm_options_overrides: { temperature: 0.7, top_p: 0.8, top_k: 20, min_p: 0 },
      },
      {
        id: "kimi_k2_5_instant",
        applies_to: ["moonshotai/kimi-k2.5*"],
        llm_options_overrides: { temperature: 0.6, top_p: 0.95 },
      },
    ].freeze

    def self.call
      seed_providers!
      seed_mock_provider! if Rails.env.development? || Rails.env.test?
      seed_openrouter_models!
    end

    def self.seed_providers!
      providers = [
        {
          name: "OpenRouter",
          api_format: "openai",
          base_url: "https://openrouter.ai/api",
          api_prefix: "/v1",
          headers: {
            "HTTP-Referer" => ENV["OPENROUTER_HTTP_REFERER"],
            "X-Title" => ENV["OPENROUTER_X_TITLE"],
          }.compact,
          llm_options_defaults: {},
        },
        {
          name: "Volcengine (火山引擎)",
          api_format: "openai",
          base_url: "https://ark.cn-beijing.volces.com/api",
          api_prefix: "/v3",
          headers: {},
          llm_options_defaults: {},
        },
        {
          name: "Ollama (Local)",
          api_format: "openai",
          base_url: "http://localhost:11434",
          api_prefix: "/v1",
          headers: {},
          llm_options_defaults: {},
        },
        {
          name: "OpenAI",
          api_format: "openai",
          base_url: "https://api.openai.com",
          api_prefix: "/v1",
          headers: {},
          llm_options_defaults: {},
        },
        {
          name: "DeepSeek",
          api_format: "openai",
          base_url: "https://api.deepseek.com",
          api_prefix: "/v1",
          headers: {},
          llm_options_defaults: {},
        },
        {
          name: "Groq",
          api_format: "openai",
          base_url: "https://api.groq.com/openai",
          api_prefix: "/v1",
          headers: {},
          llm_options_defaults: {},
        },
        {
          name: "Together AI",
          api_format: "openai",
          base_url: "https://api.together.xyz",
          api_prefix: "/v1",
          headers: {},
          llm_options_defaults: {},
        },
        {
          name: "Custom",
          api_format: "openai",
          base_url: "http://localhost:8000",
          api_prefix: "/v1",
          headers: {},
          llm_options_defaults: {},
        },
      ].freeze

      providers.each do |attrs|
        LLMProvider.find_or_create_by!(name: attrs.fetch(:name)) do |provider|
          provider.api_format = attrs.fetch(:api_format)
          provider.base_url = attrs.fetch(:base_url)
          provider.api_prefix = attrs.fetch(:api_prefix)
          provider.headers = attrs.fetch(:headers)
          provider.llm_options_defaults = attrs.fetch(:llm_options_defaults)
        end
      end
    end

    def self.seed_openrouter_models!
      openrouter = LLMProvider.find_by!(name: "OpenRouter")

      OPENROUTER_MODELS.each do |model_id|
        llm_model =
          LLMModel.find_or_create_by!(llm_provider: openrouter, model: model_id) do |m|
            m.name = model_id
            m.enabled = true

            # Seed OpenRouter capability defaults.
            m.supports_tool_calling = true
            m.supports_response_format_json_object = true
            m.supports_response_format_json_schema = true
            m.supports_streaming = true
            m.supports_parallel_tool_calls = true

            # Overrides mirroring the infra registry (kept in seeds to avoid coupling).
            if model_id.match?(/\Aanthropic\//)
              m.supports_response_format_json_schema = false
            elsif model_id.match?(/\Aopenai\//) || model_id.match?(/\Aminimax\//)
              m.supports_response_format_json_object = false
              m.supports_response_format_json_schema = false
            end

            if model_id == "minimax/minimax-m2-her"
              m.supports_tool_calling = false
              m.supports_response_format_json_object = false
              m.supports_response_format_json_schema = false
            end
          end

        sampling_entry = recommended_sampling_entry_for_model(model_id)
        default_overrides = (sampling_entry ? sampling_entry.fetch(:llm_options_overrides, {}) : {}).dup
        LLMPreset.find_or_create_by!(llm_model: llm_model, key: "default") do |p|
          p.name = "Default"
          p.comment =
            if sampling_entry
              "Production recommended sampling profile: #{sampling_entry.fetch(:id)}"
            else
              "Production recommended sampling profile: (none)"
            end
          p.llm_options_overrides = default_overrides
        end
      end
    end

    def self.seed_mock_provider!
      provider =
        LLMProvider.find_or_create_by!(name: "Mock (Local)") do |p|
          p.api_format = "openai"
          p.base_url = ENV.fetch("MOCK_LLM_BASE_URL", "http://localhost:3000")
          p.api_prefix = "/mock_llm/v1"
          p.headers = {}
          p.llm_options_defaults = {}
        end

      llm_model =
        LLMModel.find_or_create_by!(llm_provider: provider, model: "mock") do |m|
          m.name = "Mock"
          m.key = "mock"
          m.enabled = true

          m.supports_tool_calling = false
          m.supports_response_format_json_object = false
          m.supports_response_format_json_schema = false
          m.supports_streaming = true
          m.supports_parallel_tool_calls = false
        end

      LLMPreset.find_or_create_by!(llm_model: llm_model, key: "default") do |p|
        p.name = "Default"
        p.comment = "Default preset for local mock provider"
        p.llm_options_overrides = { temperature: 0.0 }
      end
    end

    def self.recommended_sampling_entry_for_model(model_id)
      model = model_id.to_s

      RECOMMENDED_SAMPLING.find do |e|
        Array(e.fetch(:applies_to, [])).any? { |pattern| File.fnmatch(pattern.to_s, model) }
      end
    end

    private_class_method :recommended_sampling_entry_for_model, :seed_mock_provider!, :seed_openrouter_models!, :seed_providers!
  end
end
