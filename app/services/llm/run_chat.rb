# frozen_string_literal: true

module LLM
  class RunChat
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
      strict: nil,
      allow_disabled: false,
      client: nil,
      pipeline: TavernKit::VibeTavern::Pipeline,
      step_options: nil
    )
      @llm_model = llm_model
      @user_text = user_text
      @history = history
      @system = system
      @context = context
      @preset = preset
      @preset_key = preset_key
      @llm_options = llm_options
      @strict = strict
      @allow_disabled = allow_disabled == true
      @client = client
      @pipeline = pipeline
      @step_options = step_options
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
      normalized_history = normalize_history(history, user_text: user_text)
      return Result.failure(errors: ["prompt is empty"], code: "EMPTY_PROMPT", value: { llm_model: llm_model }) if normalized_history.empty?

      runner_config =
        llm_model.build_runner_config(
          context: normalized_context,
          preset: selected_preset,
          pipeline: pipeline,
          step_options: step_options,
        )

      prompt_runner = TavernKit::VibeTavern::PromptRunner.new(client: effective_client)

      prompt_request =
        prompt_runner.build_request(
          runner_config: runner_config,
          history: normalized_history,
          system: system,
          strict: strict?,
          llm_options: normalize_llm_options(llm_options),
          dialect: :openai,
        )

      prompt_result = prompt_runner.perform(prompt_request)

      Result.success(
        value: {
          llm_model: llm_model,
          preset: selected_preset,
          runner_config: runner_config,
          prompt_result: prompt_result,
        },
      )
    rescue TavernKit::MaxTokensExceededError => e
      Result.failure(
        errors: [e.message],
        code: "PROMPT_TOO_LONG",
        value: {
          llm_model: llm_model,
          estimated_tokens: e.estimated_tokens,
          max_tokens: e.max_tokens,
          reserve_tokens: e.reserve_tokens,
          limit_tokens: e.limit_tokens,
        },
      )
    rescue SimpleInference::Errors::Error => e
      Result.failure(errors: [e.message], code: "LLM_REQUEST_FAILED", value: { llm_model: llm_model })
    rescue TavernKit::PipelineError, TavernKit::StrictModeError, ActiveRecord::RecordInvalid, ArgumentError => e
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
                :strict,
                :allow_disabled,
                :client,
                :pipeline,
                :step_options

    def validate_llm_model!
      raise ArgumentError, "llm_model must be a LLMModel" unless llm_model.is_a?(LLMModel)
    end

    def resolve_preset
      if preset.is_a?(LLMPreset)
        return Result.failure(errors: ["preset does not belong to llm_model"], code: "INVALID_INPUT") if preset.llm_model_id != llm_model.id

        return preset
      end

      key = preset_key.to_s.strip.downcase
      if key.present?
        found = llm_model.llm_presets.find_by(key: key)
        return Result.failure(errors: ["preset not found: #{key}"], code: "PRESET_NOT_FOUND") unless found

        return found
      end

      llm_model.llm_presets.find_by(key: "default")
    end

    def normalize_context(value)
      case value
      when nil
        nil
      when TavernKit::PromptBuilder::Context
        value
      when Hash
        normalized = TavernKit::Utils.deep_symbolize_keys(value)
        TavernKit::PromptBuilder::Context.build(normalized, type: :app)
      else
        raise ArgumentError, "context must be a Hash or TavernKit::PromptBuilder::Context"
      end
    end

    def normalize_history(value, user_text:)
      messages = Array(value).map { |m| TavernKit::ChatHistory.coerce_message(m) }

      if user_text.present?
        messages << TavernKit::PromptBuilder::Message.new(role: :user, content: user_text.to_s)
      end

      messages
    end

    def normalize_llm_options(value)
      h = value.nil? ? {} : value
      raise ArgumentError, "llm_options must be a Hash" unless h.is_a?(Hash)

      normalized = TavernKit::Utils.deep_symbolize_keys(h)
      TavernKit::Utils.assert_symbol_keys!(normalized, path: "llm_options")
      normalized
    end

    def strict?
      return strict == true unless strict.nil?

      Rails.env.test?
    end

    def effective_client
      client || llm_model.llm_provider.build_simple_inference_client
    end
  end
end
