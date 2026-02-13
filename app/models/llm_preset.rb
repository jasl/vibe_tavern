# frozen_string_literal: true

class LLMPreset < ApplicationRecord
  belongs_to :llm_model

  normalizes :key, with: ->(key) { key.to_s.strip.downcase.presence }, apply_to_nil: false

  validates :name, presence: true
  validates :key, uniqueness: { scope: :llm_model_id }, allow_nil: true

  validate :llm_options_overrides_must_be_a_hash
  validate :llm_options_overrides_must_not_include_reserved_keys

  def llm_options_overrides_symbolized
    TavernKit::Utils.deep_symbolize_keys((llm_options_overrides || {}).to_h)
  end

  private

  def llm_options_overrides_must_be_a_hash
    errors.add(:llm_options_overrides, "must be a JSON object") unless llm_options_overrides.is_a?(Hash)
  end

  def llm_options_overrides_must_not_include_reserved_keys
    return unless llm_options_overrides.is_a?(Hash)

    reserved = reserved_llm_options_keys.map(&:to_s)
    invalid = llm_options_overrides.keys.map(&:to_s) & reserved
    return if invalid.empty?

    errors.add(:llm_options_overrides, "contains reserved keys: #{invalid.sort.join(", ")}")
  end

  def reserved_llm_options_keys
    TavernKit::VibeTavern::RunnerConfig::RESERVED_LLM_OPTIONS_KEYS
  rescue NameError
    %i[model messages tools tool_choice response_format stream stream_options]
  end
end
