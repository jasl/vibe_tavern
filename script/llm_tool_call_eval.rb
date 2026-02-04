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
fix_empty_final = ENV.fetch("OPENROUTER_FIX_EMPTY_FINAL", "1") == "1"
tool_use_mode =
  ENV.fetch("OPENROUTER_TOOL_USE_MODE", "enforced").strip.downcase
tool_use_mode = "disabled" unless %w[enforced relaxed disabled].include?(tool_use_mode)
tools_enabled = tool_use_mode != "disabled"
fallback_retry_count =
  begin
    Integer(ENV.fetch("OPENROUTER_TOOL_CALLING_FALLBACK_RETRY_COUNT", "0"))
  rescue ArgumentError
    0
  end
fallback_retry_count = 0 if fallback_retry_count < 0
tool_profile = ENV.fetch("OPENROUTER_TOOL_PROFILE", "eval_minimal")

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
  "qwen/qwen3-next-80b-a3b-instruct", # Bugged
  "qwen/qwen3-vl-235b-a22b-instruct",
  "z-ai/glm-4.7",
  "z-ai/glm-4.7-flash", # Bugged
  "moonshotai/kimi-k2.5",
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
  return "TOOL_ERROR" if msg.start_with?("TOOL_ERROR:")
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
        case parsed
        when Hash
          err = parsed["error"]
          if err.is_a?(Hash)
            err["message"] || parsed["message"] || raw
          elsif err.is_a?(String)
            err
          else
            parsed["message"] || raw
          end
        when String
          parsed
        when Array
          first_hash = parsed.find { |v| v.is_a?(Hash) }
          if first_hash
            err = first_hash["error"]
            if err.is_a?(Hash)
              err["message"] || first_hash["message"] || raw
            elsif err.is_a?(String)
              err
            else
              first_hash["message"] || raw
            end
          else
            raw
          end
        else
          raw
        end
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
rescue StandardError
  nil
end

system =
  if tools_enabled
    <<~SYS.strip
      You are a tool-using assistant.
      Rules:
      - Always call `state_get` first.
      - IMPORTANT: Call at most ONE tool per assistant message. Do NOT call multiple tools in a single response.
      - Then call `state_patch` to set `/draft/foo` to string value "bar".
        - Only change the `/draft/foo` path. Do not change other draft keys.
      - Do NOT ask the user for confirmation. The target value is always "bar", and it is already approved.
      - If a tool returns ok=false, read `errors[]`, fix your arguments, and call the tool again.
      - Do NOT reply "Done." until AFTER you have received a successful (ok=true) tool result for `state_patch`.
      - Do NOT call `facts_commit` (it is not available).
      - After tools are done, reply with a single sentence: "Done."

      Examples (JSON args):
      - state_get: {"workspace_id":"..."}
      - state_patch: {"request_id":"r1","ops":[{"op":"set","path":"/draft/foo","value":"bar"}]}
    SYS
  else
    <<~SYS.strip
      Tool calling is disabled for this run.
      Reply with a single sentence: "Done."
    SYS
  end

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
      runtime:
        TavernKit::Runtime::Base.build(
          {
            tool_calling: {
              tool_use_mode: tool_use_mode,
              fallback_retry_count: fallback_retry_count,
              fix_empty_final: fix_empty_final,
            },
          },
          type: :app,
        ),
      registry:
        if tools_enabled && tool_profile == "eval_minimal"
          TavernKit::VibeTavern::ToolCalling::EvalToolRegistry.new
        else
          nil
        end,
      system: system,
      strict: false,
    )

  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  ok = true
  error = nil
  error_status = nil
  error_body = nil
  error_raw_body = nil
  assistant_text = nil
  trace = nil
  history = nil

  begin
    result = runner.run(user_text: "workspace_id=#{workspace.id}")
    assistant_text = result[:assistant_text]
    trace = result[:trace]
    history =
      Array(result[:history]).map do |m|
        if m.respond_to?(:to_serializable_hash)
          m.to_serializable_hash
        else
          { role: m.respond_to?(:role) ? m.role : nil, content: m.respond_to?(:content) ? m.content : m.to_s }
        end
      end

    fail_reasons = []
    fail_reasons << %(assistant_text != "Done.") unless assistant_text.to_s.strip == "Done."
    fail_reasons << %(draft["foo"] != "bar") if tools_enabled && workspace.draft["foo"] != "bar"

    unless fail_reasons.empty?
      tool_calls_seen = tools_enabled && Array(trace).any? { |t| t.is_a?(Hash) && t.dig(:response_summary, :has_tool_calls) == true }
      if tools_enabled && !tool_calls_seen
        error = "NO_TOOL_CALLS: assistant did not request any tool calls"
      else
        error = "ASSERTION_FAILED: #{fail_reasons.join("; ")}"
      end
      ok = false
    end
  rescue TavernKit::VibeTavern::ToolCalling::ToolLoopRunner::ToolUseError => e
    ok = false
    error = "#{e.code}: #{e.message}"
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
    history: history,
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
  tool_use_mode: tool_use_mode,
  tool_calling_fallback_retry_count: fallback_retry_count,
  tool_profile: tool_profile,
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
puts "tool_use_mode: #{tool_use_mode}"
puts "tool_calling_fallback_retry_count: #{fallback_retry_count}"
puts "fix_empty_final: #{fix_empty_final}"
puts "tool_profile: #{tool_profile}"
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
