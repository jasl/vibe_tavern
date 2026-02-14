# frozen_string_literal: true

class LLMProvider < ApplicationRecord
  API_FORMATS = %w[openai].freeze

  encrypts :api_key

  has_many :llm_models, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :base_url, presence: true
  validates :api_format, presence: true, inclusion: { in: API_FORMATS }
  validates :message_overhead_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :api_prefix_must_not_be_nil

  validate :headers_must_be_a_hash
  validate :llm_options_defaults_must_be_a_hash
  validate :llm_options_defaults_must_not_include_reserved_keys

  def build_simple_inference_client(timeout: nil, open_timeout: nil, read_timeout: nil, adapter: nil)
    raise ArgumentError, "api_format not supported: #{api_format.inspect}" unless api_format == "openai"

    SimpleInference::Client.new(
      base_url: base_url,
      api_prefix: api_prefix,
      api_key: api_key,
      headers: headers_for_simple_inference,
      timeout: timeout,
      open_timeout: open_timeout,
      read_timeout: read_timeout,
      adapter: adapter,
    )
  end

  def enable_all!
    llm_models.update_all(enabled: true, updated_at: Time.current)
    self
  end

  def disable_all!
    llm_models.update_all(enabled: false, updated_at: Time.current)
    self
  end

  def headers_for_simple_inference
    (headers || {}).to_h.transform_keys(&:to_s)
  end

  def llm_options_defaults_symbolized
    AgentCore::Utils.deep_symbolize_keys((llm_options_defaults || {}).to_h)
  end

  private

  def headers_must_be_a_hash
    errors.add(:headers, "must be a JSON object") unless headers.is_a?(Hash)
  end

  def llm_options_defaults_must_be_a_hash
    errors.add(:llm_options_defaults, "must be a JSON object") unless llm_options_defaults.is_a?(Hash)
  end

  def llm_options_defaults_must_not_include_reserved_keys
    return unless llm_options_defaults.is_a?(Hash)

    reserved = reserved_llm_options_keys.map(&:to_s)
    invalid = llm_options_defaults.keys.map(&:to_s) & reserved
    return if invalid.empty?

    errors.add(:llm_options_defaults, "contains reserved keys: #{invalid.sort.join(", ")}")
  end

  def api_prefix_must_not_be_nil
    errors.add(:api_prefix, "can't be nil") if api_prefix.nil?
  end

  def reserved_llm_options_keys
    AgentCore::Contrib::OpenAI::RESERVED_CHAT_COMPLETIONS_KEYS
  end
end
