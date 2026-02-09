#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"

# Default settings
ENV["RAILS_ENV"] ||= "development"

# Load Rails environment (for SimpleInference + app dependencies)
require_relative "../config/environment"

api_key = ENV.fetch("OPENROUTER_API_KEY", "").to_s.strip
if api_key.empty?
  warn "Missing OPENROUTER_API_KEY."
  exit 2
end

base_url = ENV.fetch("OPENROUTER_BASE_URL", "https://openrouter.ai/api").to_s
api_prefix = ENV.fetch("OPENROUTER_API_PREFIX", "/v1").to_s

models =
  ENV.fetch("OPENROUTER_MODELS", ENV.fetch("OPENROUTER_MODEL", "")).to_s
    .split(",")
    .map(&:strip)
    .reject(&:empty?)

if models.empty?
  warn "Missing OPENROUTER_MODELS (comma-separated) or OPENROUTER_MODEL."
  exit 2
end

format = ENV.fetch("FORMAT", "table").to_s.strip.downcase
format = "table" unless %w[table jsonl].include?(format)

client = SimpleInference::Client.new(base_url: base_url, api_key: api_key, api_prefix: api_prefix)

prompt_id = ENV.fetch("PROMPT_ID", "default").to_s.strip
prompt_id = "default" if prompt_id.empty?

user_text =
  case prompt_id
  when "short"
    "Hello! 这是一个测试。"
  else
    <<~TEXT
      Mixed-language token estimation sanity prompt.

      English: Please respond with a single word: OK
      Chinese: 这是一个测试。
      Japanese: これはテストです。
      Korean: 이것은 테스트입니다.

      Code:
      ```ruby
      def hello(name)
        puts "Hello, #{name}"
      end
      ```

      URL: https://example.com/DO_NOT_TRANSLATE_001
    TEXT
  end

messages = [
  { role: "system", content: "You are a helpful assistant." },
  { role: "user", content: user_text },
]

estimator = TavernKit::TokenEstimator.default

def safe_float(v)
  Float(v)
rescue ArgumentError, TypeError
  nil
end

def safe_int(v)
  Integer(v)
rescue ArgumentError, TypeError
  nil
end

rows =
  models.map do |model|
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    usage = nil
    error = nil

    begin
      resp =
        client.chat_completions(
          model: model,
          messages: messages,
          temperature: 0,
          max_tokens: 1,
        )
      body = resp.body.is_a?(Hash) ? resp.body : {}
      usage = body["usage"].is_a?(Hash) ? body["usage"] : nil
    rescue StandardError => e
      error = "#{e.class}: #{e.message}"
    end

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    estimated_content_tokens =
      messages.sum do |m|
        estimator.estimate(m[:content].to_s, model_hint: model)
      end

    info = estimator.describe(model_hint: model)

    prompt_tokens = usage ? safe_int(usage["prompt_tokens"]) : nil
    completion_tokens = usage ? safe_int(usage["completion_tokens"]) : nil
    total_tokens = usage ? safe_int(usage["total_tokens"]) : nil

    diff = prompt_tokens ? (prompt_tokens - estimated_content_tokens) : nil
    ratio = prompt_tokens ? safe_float(prompt_tokens).fdiv(estimated_content_tokens) : nil

    {
      model: model,
      ok: error.nil?,
      error: error,
      elapsed_ms: elapsed_ms,
      usage: usage,
      estimated_content_tokens: estimated_content_tokens,
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: total_tokens,
      diff_prompt_minus_estimated: diff,
      ratio_prompt_over_estimated: ratio,
      estimator: info,
    }
  end

case format
when "jsonl"
  rows.each { |r| puts JSON.generate(r) }
else
  puts "Token Estimator Sanity"
  puts "prompt_id: #{prompt_id}"
  puts "models: #{models.join(", ")}"
  puts "format: #{format}"
  puts
  puts "NOTE: estimated_content_tokens counts only message content (no role/tool/schema overhead)."
  puts

  header = [
    "model",
    "prompt_tokens",
    "estimated_content_tokens",
    "diff",
    "ratio",
    "backend",
    "encoding",
    "source",
    "ms",
  ]
  puts header.join("\t")

  rows.each do |r|
    est = r.fetch(:estimated_content_tokens)
    prompt = r[:prompt_tokens]
    diff = r[:diff_prompt_minus_estimated]
    ratio = r[:ratio_prompt_over_estimated]
    info = r.fetch(:estimator, {})

    puts(
      [
        r.fetch(:model),
        prompt || "(n/a)",
        est,
        diff || "(n/a)",
        ratio ? format("%.3f", ratio) : "(n/a)",
        info[:backend] || "(n/a)",
        info[:encoding] || "(n/a)",
        info[:source] || "(n/a)",
        r.fetch(:elapsed_ms),
      ].join("\t"),
    )

    next if r[:ok] == true

    warn "ERROR: #{r.fetch(:model)}: #{r[:error]}"
  end
end
