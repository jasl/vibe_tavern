# frozen_string_literal: true

require "agent_core"
require "agent_core/resources/provider/simple_inference_provider"

module LLM
  class RunToolChat
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(
      llm_model:,
      user_text: nil,
      history: nil,
      system: nil,
      context: nil,
      preset: nil,
      preset_key: nil,
      llm_options: nil,
      allow_disabled: false,
      client: nil,
      tooling_key: "default",
      context_keys: []
    )
      @llm_model = llm_model
      @user_text = user_text
      @history = history
      @system = system
      @context = context
      @preset = preset
      @preset_key = preset_key
      @llm_options = llm_options
      @allow_disabled = allow_disabled == true
      @client = client
      @tooling_key = tooling_key
      @context_keys = context_keys
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
      history_messages = normalize_history(history)
      normalized_user_text = normalize_user_text(user_text)

      if history_messages.empty? && normalized_user_text.empty?
        return Result.failure(errors: ["prompt is empty"], code: "EMPTY_PROMPT", value: { llm_model: llm_model })
      end

      effective_llm_options = build_effective_llm_options(selected_preset, llm_options)

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

      normalized_tooling_key = normalize_tooling_key(tooling_key)
      execution_context_attributes = normalize_execution_context_attributes(normalized_context, context_keys: context_keys)

      tools_registry = LLM::Tooling.registry(tooling_key: normalized_tooling_key, context_attributes: execution_context_attributes)
      tool_policy = LLM::Tooling.policy(tooling_key: normalized_tooling_key, context_attributes: execution_context_attributes)

      session =
        AgentCore::Contrib::AgentSession.new(
          provider: provider,
          model: llm_model.model,
          system_prompt: system.to_s,
          history: history_messages,
          llm_options: effective_llm_options,
          token_counter: token_counter,
          context_window: context_window,
          reserved_output_tokens: reserved_output_tokens,
          tools_registry: tools_registry,
          tool_policy: tool_policy,
          tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
          capabilities: llm_model.capabilities_overrides,
        )

      run_result =
        session.chat(
          normalized_user_text,
          language_policy: normalized_context.fetch(:language_policy, nil),
          context: execution_context_attributes,
        )

      if run_result.respond_to?(:awaiting_tool_results?) && run_result.awaiting_tool_results?
        persisted_context_keys = normalize_context_keys(context_keys)

        continuation_payload =
          AgentCore::PromptRunner::ContinuationCodec.dump(
            run_result.continuation,
            context_keys: persisted_context_keys,
            include_traces: true,
          )

        record =
          ContinuationRecord.create!(
            run_id: run_result.run_id,
            continuation_id: continuation_payload.fetch("continuation_id"),
            parent_continuation_id: continuation_payload.fetch("parent_continuation_id", nil),
            llm_model: llm_model,
            tooling_key: normalized_tooling_key,
            status: "current",
            payload: continuation_payload,
          )

        task_payload =
          AgentCore::PromptRunner::ToolTaskCodec.dump(
            run_result.continuation,
            context_keys: persisted_context_keys,
          )

        enqueue_missing_tool_tasks!(task_payload, tooling_key: normalized_tooling_key)

        return Result.success(
          value: {
            llm_model: llm_model,
            preset: selected_preset,
            context: normalized_context,
            run_id: run_result.run_id,
            continuation_id: record.continuation_id,
            run_result: run_result,
          },
        )
      end

      Result.success(
        value: {
          llm_model: llm_model,
          preset: selected_preset,
          context: normalized_context,
          run_id: run_result.run_id,
          continuation_id: nil,
          run_result: run_result,
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
                :user_text,
                :history,
                :system,
                :context,
                :preset,
                :preset_key,
                :llm_options,
                :allow_disabled,
                :client,
                :tooling_key,
                :context_keys

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

    def normalize_user_text(value)
      text = value.to_s
      text = "" if text.strip.empty?
      text
    end

    def build_effective_llm_options(selected_preset, user_llm_options)
      user_llm_options = normalize_llm_options(user_llm_options)
      provider_defaults = llm_model.llm_provider.llm_options_defaults_symbolized
      preset_overrides = selected_preset.is_a?(LLMPreset) ? selected_preset.llm_options_overrides_symbolized : {}

      AgentCore::Contrib::Utils.deep_merge_hashes(
        provider_defaults,
        preset_overrides,
        user_llm_options,
      )
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

    def normalize_tooling_key(value)
      key = value.to_s.strip
      key = "default" if key.empty?
      key
    end

    def normalize_context_keys(value)
      keys = Array(value)
      keys
        .map { |k| k.to_s.strip }
        .reject(&:empty?)
        .map(&:to_sym)
        .uniq
    end

    def normalize_execution_context_attributes(context_hash, context_keys:)
      allowed = normalize_context_keys(context_keys)
      return {} if allowed.empty?

      allowed.each_with_object({}) do |key, out|
        next unless context_hash.key?(key)

        out[key] = context_hash.fetch(key)
      end
    end

    def enqueue_missing_tool_tasks!(task_payload, tooling_key:)
      run_id = task_payload.fetch("run_id").to_s
      context_attributes = task_payload.fetch("context_attributes", {})
      tasks = Array(task_payload.fetch("tasks"))

      tool_call_ids = tasks.map { |t| t.fetch("tool_call_id").to_s }
      existing_ids = ToolResultRecord.where(run_id: run_id, tool_call_id: tool_call_ids).pluck(:tool_call_id)
      existing = existing_ids.each_with_object({}) { |id, out| out[id.to_s] = true }

      tasks.each do |t|
        tool_call_id = t.fetch("tool_call_id").to_s
        next if existing.key?(tool_call_id)

        LLM::ExecuteToolCallJob.perform_later(
          run_id: run_id,
          tooling_key: tooling_key,
          tool_call_id: tool_call_id,
          executed_name: t.fetch("executed_name").to_s,
          arguments: t.fetch("arguments"),
          context_attributes: context_attributes,
        )
      end
    end

    def effective_client
      client || llm_model.llm_provider.build_simple_inference_client
    end
  end
end
