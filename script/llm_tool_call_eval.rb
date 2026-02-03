#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

# Default settings
ENV["RAILS_ENV"] ||= "development"

# Load Rails environment
require_relative "../config/environment"

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
fix_empty_final = ENV["OPENROUTER_FIX_EMPTY_FINAL"].to_s == "1"

DEFAULT_MODELS = [
  "deepseek/deepseek-v3.2",
  "deepseek/deepseek-chat-v3-0324",
  "x-ai/grok-4.1-fast",
  # "minimax/minimax-m2-her", # Not support tool use
  "google/gemini-2.5-flash",
  "google/gemini-3-flash-preview",
  "google/gemini-3-pro-preview",
  "anthropic/claude-opus-4.5",
  "openai/gpt-5.2-chat",
  "openai/gpt-5.2",
  "qwen/qwen3-vl-30b-a3b-instruct",
  "qwen/qwen3-next-80b-a3b-instruct",
  "qwen/qwen3-vl-235b-a22b-instruct",
  "z-ai/glm-4.7",
  "z-ai/glm-4.7-flash",
].freeze

models = ENV.fetch("OPENROUTER_MODELS", ENV["OPENROUTER_MODEL"].to_s).split(",").map(&:strip).reject(&:empty?)
models = DEFAULT_MODELS if models.empty?

headers = {}
headers["HTTP-Referer"] = ENV["OPENROUTER_HTTP_REFERER"] if ENV["OPENROUTER_HTTP_REFERER"]
headers["X-Title"] = ENV["OPENROUTER_X_TITLE"] if ENV["OPENROUTER_X_TITLE"]

def truncate(str, max_chars: 220)
  s = str.to_s
  return s if s.length <= max_chars

  "#{s[0, max_chars]}…"
end

def error_category(message, status: nil)
  msg = message.to_s
  return "ASSERTION_FAILED" if msg.start_with?("ASSERTION_FAILED:")
  return "NO_TOOL_CALLS" if msg.start_with?("NO_TOOL_CALLS:")
  return "NO_TOOL_USE_ENDPOINT" if msg.include?("No endpoints found that support tool use")

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
        parsed.dig("error", "message") || parsed["message"] || raw
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
end

system = <<~SYS.strip
  You are a tool-using assistant.
  Rules:
  - Always call `state_get` first.
  - IMPORTANT: Call at most ONE tool per assistant message. Do NOT call multiple tools in a single response.
  - Then call `state_patch` to set `/draft/foo` to string value "bar".
    - Only change the `/draft/foo` path. Do not change other draft keys.
  - Do NOT call `facts_commit` (it is not available).
  - After tools are done, reply with a single sentence: "Done."

  Examples (JSON args):
  - state_get: {"workspace_id":"..."}
  - state_patch: {"ops":[{"op":"set","path":"/draft/foo","value":"bar"}]}
SYS

timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
out_dir = Rails.root.join("tmp", "llm_tool_call_eval_reports", timestamp)
FileUtils.mkdir_p(out_dir)

reports = []

models.each do |model|
  idx = reports.length + 1
  total = models.length
  $stderr.puts("[#{idx}/#{total}] testing #{model}...")
  $stderr.flush

  workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new

  client = SimpleInference::Client.new(
    base_url: base_url,
    api_key: api_key,
    headers: headers,
    api_prefix: api_prefix,
  )

  runner =
    TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(
      client: client,
      model: model,
      workspace: workspace,
      system: system,
      strict: false,
      fix_empty_final: fix_empty_final,
    )

  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  ok = true
  error = nil
  error_status = nil
  error_body = nil
  error_raw_body = nil
  assistant_text = nil
  trace = nil

  begin
    result = runner.run(user_text: "workspace_id=#{workspace.id}")
    assistant_text = result[:assistant_text]
    trace = result[:trace]

    fail_reasons = []
    fail_reasons << %(assistant_text != "Done.") unless assistant_text.to_s.strip == "Done."
    fail_reasons << %(draft["foo"] != "bar") unless workspace.draft["foo"] == "bar"

    unless fail_reasons.empty?
      tool_calls_seen = Array(trace).any? { |t| t.is_a?(Hash) && t.dig(:response_summary, :has_tool_calls) == true }
      if !tool_calls_seen
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
  rescue StandardError => e
    ok = false
    error = truncate("#{e.class}: #{e.message}", max_chars: 400)
  end

  elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

  report = {
    model: model,
    ok: ok,
    elapsed_ms: elapsed_ms,
    assistant_text: assistant_text,
    draft: workspace.draft,
    error: error,
    error_status: error_status,
    error_body: error_body,
    error_raw_body: error_raw_body,
    error_category: ok ? nil : error_category(error, status: error_status),
    trace: trace,
  }

  # Always write per-model report (easier to share only the failing ones).
  safe_name = model.gsub(%r{[^a-zA-Z0-9_.-]+}, "__")
  File.write(out_dir.join("#{safe_name}.json"), JSON.pretty_generate(report))

  reports << report

  status_str = report[:ok] ? "OK" : "FAIL"
  extra =
    if report[:ok]
      ""
    elsif report[:error_category] == "NO_TOOL_USE_ENDPOINT"
      " (no tool-use endpoint)"
    elsif report[:error_category] == "NO_TOOL_CALLS"
      " (no tool calls requested)"
    else
      ""
    end
  $stderr.puts("[#{idx}/#{total}] #{status_str} #{model} (#{elapsed_ms}ms)#{extra}")
  $stderr.flush
end

summary = {
  ts: Time.now.utc.iso8601,
  base_url: base_url,
  api_prefix: api_prefix,
  fix_empty_final: fix_empty_final,
  output_dir: out_dir.to_s,
  models: reports,
}

File.write(out_dir.join("summary.json"), JSON.pretty_generate(summary))

successes = reports.count { |r| r[:ok] }
failures = reports.count { |r| !r[:ok] }

puts "LLM Tool Call Eval"
puts "ts: #{summary[:ts]}"
puts "base_url: #{base_url}"
puts "api_prefix: #{api_prefix}"
puts "models: #{reports.size} (ok=#{successes}, fail=#{failures})"
puts "full report: #{out_dir.relative_path_from(Rails.root)}"
puts

header = ["model", "ok", "ms", "status", "category", "error"]
rows =
  reports.map do |r|
    hint = provider_error_hint(r)
    err = r[:ok] ? "-" : truncate(hint || r[:error].to_s, max_chars: 120)
    [
      r[:model].to_s,
      r[:ok] ? "OK" : "FAIL",
      r[:elapsed_ms].to_s,
      r[:error_status] ? r[:error_status].to_s : "-",
      r[:error_category] || "-",
      err,
    ]
  end

widths = header.map.with_index { |h, idx| ([h.length] + rows.map { |row| row[idx].length }).max }

fmt = widths.map { |w| "%-#{w}s" }.join(" | ")
sep = widths.map { |w| "-" * w }.join("-|-")

puts format(fmt, *header)
puts sep
rows.each { |row| puts format(fmt, *row) }
