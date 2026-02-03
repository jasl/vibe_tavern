#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "json"
require "time"

require "simple_inference"
require "tavern_kit"

# App-owned pipeline + tool loop (DB-free).
require_relative "../lib/tavern_kit/vibe_tavern/middleware/prepare"
require_relative "../lib/tavern_kit/vibe_tavern/middleware/plan_assembly"
require_relative "../lib/tavern_kit/vibe_tavern/pipeline"
require_relative "../lib/tavern_kit/vibe_tavern"

require_relative "../lib/tavern_kit/vibe_tavern/tool_calling/workspace"
require_relative "../lib/tavern_kit/vibe_tavern/tool_calling/tool_registry"
require_relative "../lib/tavern_kit/vibe_tavern/tool_calling/tool_dispatcher"
require_relative "../lib/tavern_kit/vibe_tavern/tool_calling/tool_loop_runner"

api_key = ENV["OPENROUTER_API_KEY"].to_s
if api_key.empty?
  warn "Missing OPENROUTER_API_KEY (this script is for live eval via OpenRouter)."
  exit 2
end

base_url = ENV.fetch("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1")
models = ENV.fetch("OPENROUTER_MODELS", ENV["OPENROUTER_MODEL"].to_s).split(",").map(&:strip).reject(&:empty?)
if models.empty?
  warn "Missing OPENROUTER_MODEL or OPENROUTER_MODELS"
  exit 2
end

headers = {}
headers["HTTP-Referer"] = ENV["OPENROUTER_HTTP_REFERER"] if ENV["OPENROUTER_HTTP_REFERER"]
headers["X-Title"] = ENV["OPENROUTER_X_TITLE"] if ENV["OPENROUTER_X_TITLE"]

system = <<~SYS.strip
  You are a tool-using assistant.
  Rules:
  - Always call `state.get` first.
  - Then call `state.patch` to set `/draft/foo` to string value "bar".
  - Do NOT call `facts.commit` (it is not available).
  - After tools are done, reply with a single sentence: "Done."
SYS

reports = []

models.each do |model|
  workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new

  client = SimpleInference::Client.new(
    base_url: base_url,
    api_key: api_key,
    headers: headers,
  )

  runner =
    TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(
      client: client,
      model: model,
      workspace: workspace,
      system: system,
      strict: false,
    )

  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  ok = true
  error = nil
  assistant_text = nil
  trace = nil

  begin
    result = runner.run(user_text: "workspace_id=#{workspace.id}")
    assistant_text = result[:assistant_text]
    trace = result[:trace]

    ok &&= (assistant_text.to_s.strip == "Done.")
    ok &&= (workspace.draft["foo"] == "bar")
  rescue StandardError => e
    ok = false
    error = "#{e.class}: #{e.message}"
  end

  elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

  reports << {
    model: model,
    ok: ok,
    elapsed_ms: elapsed_ms,
    assistant_text: assistant_text,
    draft: workspace.draft,
    error: error,
    trace: trace,
  }
end

puts JSON.pretty_generate(
  {
    ts: Time.now.utc.iso8601,
    base_url: base_url,
    models: reports,
  }
)
