# frozen_string_literal: true

require "agent_core"
require "agent_core/resources/provider/simple_inference_provider"

module LLM
  class RunDirectives
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(
      llm_model:,
      history: nil,
      system: nil,
      context: nil,
      preset: nil,
      preset_key: nil,
      llm_options: nil,
      directives_config: nil,
      structured_output_options: nil,
      result_validator: nil,
      allow_disabled: false,
      client: nil
    )
      @llm_model = llm_model
      @history = history
      @system = system
      @context = context
      @preset = preset
      @preset_key = preset_key
      @llm_options = llm_options
      @directives_config = directives_config
      @structured_output_options = structured_output_options
      @result_validator = result_validator
      @allow_disabled = allow_disabled == true
      @client = client
    end

    def call
      validate_llm_model!

      unless allow_disabled
        return Result.failure(errors: ["LLMModel is disabled"], code: "MODEL_DISABLED", value: { llm_model: llm_model }) unless llm_model.enabled?
      end

      selected_preset_result = resolve_preset
      return selected_preset_result if selected_preset_result.is_a?(Result)

      selected_preset = selected_preset_result
      normalized_context = normalize_context(context)
      messages = normalize_history(history)
      return Result.failure(errors: ["prompt is empty"], code: "EMPTY_PROMPT", value: { llm_model: llm_model }) if messages.empty?

      user_llm_options = normalize_llm_options(llm_options)
      provider_defaults = llm_model.llm_provider.llm_options_defaults_symbolized
      preset_overrides = selected_preset.is_a?(LLMPreset) ? selected_preset.llm_options_overrides_symbolized : {}

      effective_llm_options =
        AgentCore::Contrib::Utils.deep_merge_hashes(
          provider_defaults,
          preset_overrides,
          user_llm_options,
        )

      reserved_output_tokens = Integer(effective_llm_options.fetch(:max_tokens, 0), exception: false) || 0
      reserved_output_tokens = 0 if reserved_output_tokens.negative?

      context_window =
        if llm_model.context_window_tokens.to_i.positive?
          llm_model.context_window_tokens.to_i
        end

      token_counter =
        build_token_counter(
          normalized_context,
          default_model_hint: llm_model.model,
          per_message_overhead: llm_model.effective_message_overhead_tokens.to_i,
        )

      provider =
        AgentCore::Resources::Provider::SimpleInferenceProvider.new(
          client: effective_client,
        )

      session =
        AgentCore::Contrib::AgentSession.new(
          provider: provider,
          model: llm_model.model,
          system_prompt: system.to_s,
          history: messages,
          llm_options: effective_llm_options,
          token_counter: token_counter,
          context_window: context_window,
          reserved_output_tokens: reserved_output_tokens,
          directives_config: normalize_directives_config(directives_config),
          capabilities: llm_model.capabilities_overrides,
        )

      directives_result =
        session.directives(
          language_policy: normalized_context.fetch(:language_policy, nil),
          structured_output_options: normalize_structured_output_options(structured_output_options),
          result_validator: result_validator,
        )

      Result.success(
        value: {
          llm_model: llm_model,
          preset: selected_preset,
          context: normalized_context,
          directives_result: directives_result,
        },
      )
    rescue AgentCore::ContextWindowExceededError => e
      Result.failure(
        errors: [e.message],
        code: "PROMPT_TOO_LONG",
        value: {
          llm_model: llm_model,
          estimated_tokens: e.estimated_tokens,
          max_tokens: e.context_window,
          reserve_tokens: e.reserved_output,
          limit_tokens: e.limit,
        },
      )
    rescue AgentCore::ProviderError, SimpleInference::Errors::Error => e
      Result.failure(errors: [e.message], code: "LLM_REQUEST_FAILED", value: { llm_model: llm_model })
    rescue ActiveRecord::RecordInvalid, ArgumentError => e
      Result.failure(errors: [e.message], code: "INVALID_INPUT", value: { llm_model: llm_model })
    end

    private

    attr_reader :llm_model,
                :history,
                :system,
                :context,
                :preset,
                :preset_key,
                :llm_options,
                :directives_config,
                :structured_output_options,
                :result_validator,
                :allow_disabled,
                :client

    def validate_llm_model!
      raise ArgumentError, "llm_model must be a LLMModel" unless llm_model.is_a?(LLMModel)
    end

    def resolve_preset
      if preset.is_a?(LLMPreset)
        return Result.failure(errors: ["preset does not belong to llm_model"], code: "INVALID_INPUT") if preset.llm_model_id != llm_model.id

        return preset
      end

      key = preset_key.to_s.strip.downcase
      unless key.empty?
        found = llm_model.llm_presets.find_by(key: key)
        return Result.failure(errors: ["preset not found: #{key}"], code: "PRESET_NOT_FOUND") unless found

        return found
      end

      llm_model.llm_presets.find_by(key: "default")
    end

    def normalize_context(value)
      case value
      when nil
        {}
      when Hash
        AgentCore::Utils.deep_symbolize_keys(value)
      else
        raise ArgumentError, "context must be a Hash"
      end
    end

    def normalize_history(value)
      AgentCore::Contrib::OpenAIHistory.coerce_messages(value)
    end

    def normalize_llm_options(value)
      h = value.nil? ? {} : value
      raise ArgumentError, "llm_options must be a Hash" unless h.is_a?(Hash)

      normalized = AgentCore::Utils.deep_symbolize_keys(h)
      AgentCore::Utils.assert_symbol_keys!(normalized, path: "llm_options")

      reserved = normalized.keys & AgentCore::Contrib::OpenAI::RESERVED_CHAT_COMPLETIONS_KEYS
      if reserved.any?
        raise ArgumentError, "llm_options contains reserved keys: #{reserved.map(&:to_s).sort.inspect}"
      end

      normalized
    end

    def normalize_directives_config(value)
      case value
      when nil
        {}
      when Hash
        AgentCore::Utils.deep_symbolize_keys(value)
      else
        raise ArgumentError, "directives_config must be a Hash"
      end
    end

    def normalize_structured_output_options(value)
      case value
      when nil
        nil
      when Hash
        AgentCore::Utils.deep_symbolize_keys(value)
      else
        raise ArgumentError, "structured_output_options must be a Hash"
      end
    end

    def build_token_counter(context_hash, default_model_hint:, per_message_overhead:)
      token_estimation = context_hash.fetch(:token_estimation, nil)
      token_estimation = {} unless token_estimation.is_a?(Hash)

      token_estimator = token_estimation.fetch(:token_estimator, nil)
      if token_estimator && !token_estimator.respond_to?(:estimate)
        raise ArgumentError, "token_estimation.token_estimator must respond to #estimate"
      end

      model_hint = token_estimation.fetch(:model_hint, nil)
      model_hint = default_model_hint if model_hint.to_s.strip.empty?

      if token_estimator
        return AgentCore::Contrib::TokenCounter::Estimator.new(
          token_estimator: token_estimator,
          model_hint: model_hint,
          per_message_overhead: per_message_overhead,
        )
      end

      registry = token_estimation.fetch(:registry, nil)
      if registry
        raise ArgumentError, "token_estimation.registry must be a Hash" unless registry.is_a?(Hash)

        token_estimator = AgentCore::Contrib::TokenEstimator.new(registry: registry)
        return AgentCore::Contrib::TokenCounter::Estimator.new(
          token_estimator: token_estimator,
          model_hint: AgentCore::Contrib::TokenEstimation.canonical_model_hint(model_hint),
          per_message_overhead: per_message_overhead,
        )
      end

      begin
        token_estimator = AgentCore::Contrib::TokenEstimation.estimator
        return AgentCore::Contrib::TokenCounter::Estimator.new(
          token_estimator: token_estimator,
          model_hint: AgentCore::Contrib::TokenEstimation.canonical_model_hint(model_hint),
          per_message_overhead: per_message_overhead,
        )
      rescue AgentCore::Contrib::TokenEstimation::ConfigurationError
      end

      AgentCore::Contrib::TokenCounter::HeuristicWithOverhead.new(
        per_message_overhead: per_message_overhead,
      )
    end

    def effective_client
      client || llm_model.llm_provider.build_simple_inference_client
    end
  end
end
