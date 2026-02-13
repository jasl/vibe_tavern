# frozen_string_literal: true

class LLMModel < ApplicationRecord
  belongs_to :llm_provider
  has_many :llm_presets, dependent: :destroy

  scope :enabled, -> { where(enabled: true) }

  normalizes :key, with: ->(key) { key.to_s.strip.downcase.presence }, apply_to_nil: false

  validates :name, presence: true
  validates :key, uniqueness: true, allow_nil: true
  validates :model, presence: true, uniqueness: { scope: :llm_provider_id }
  validates :context_window_tokens,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :message_overhead_tokens,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            allow_blank: true

  def capabilities_overrides
    {
      supports_tool_calling: supports_tool_calling,
      supports_response_format_json_object: supports_response_format_json_object,
      supports_response_format_json_schema: supports_response_format_json_schema,
      supports_streaming: supports_streaming,
      supports_parallel_tool_calls: supports_parallel_tool_calls,
    }
  end

  def effective_message_overhead_tokens
    if message_overhead_tokens.blank?
      return llm_provider.message_overhead_tokens
    end

    message_overhead_tokens
  end

  def context_window_tokens_limit?
    context_window_tokens.to_i.positive?
  end

  def build_runner_config(context: nil, preset: nil, step_options: nil, pipeline: TavernKit::VibeTavern::Pipeline)
    effective_llm_defaults =
      TavernKit::Utils.deep_merge_hashes(
        llm_provider.llm_options_defaults_symbolized,
        preset.is_a?(LLMPreset) ? preset.llm_options_overrides_symbolized : {},
      )

    base_step_options_from_db = {
      max_tokens: {
        max_tokens: context_window_tokens,
        reserve_tokens: ->(state) { Integer((state.llm_options || {})[:max_tokens] || 0) },
        mode: :error,
        message_overhead_tokens: effective_message_overhead_tokens,
      },
    }

    effective_step_options =
      TavernKit::Utils.deep_merge_hashes(
        base_step_options_from_db,
        step_options.is_a?(Hash) ? step_options : {},
      )

    TavernKit::VibeTavern::RunnerConfig.build(
      provider: llm_provider.api_format,
      model: model,
      context: context,
      pipeline: pipeline,
      step_options: effective_step_options,
      llm_options_defaults: effective_llm_defaults,
      capabilities_overrides: capabilities_overrides,
    )
  end
end
