#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
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
tool_failure_policy =
  ENV.fetch("OPENROUTER_TOOL_FAILURE_POLICY", "fatal").strip.downcase
tool_failure_policy = "fatal" unless %w[fatal tolerated].include?(tool_failure_policy)
tools_enabled = tool_use_mode != "disabled"
fallback_retry_count =
  begin
    Integer(ENV.fetch("OPENROUTER_TOOL_CALLING_FALLBACK_RETRY_COUNT", "0"))
  rescue ArgumentError
    0
  end
fallback_retry_count = 0 if fallback_retry_count < 0
tool_allowlist =
  ENV.fetch("OPENROUTER_TOOL_ALLOWLIST", "")
    .split(",")
    .map(&:strip)
    .reject(&:empty?)
if tool_allowlist.any? { |n| %w[all full *].include?(n.to_s.strip.downcase) }
  tool_allowlist = nil
elsif tool_allowlist.empty? && tools_enabled
  tool_allowlist = %w[state_get state_patch]
elsif tool_allowlist.empty?
  tool_allowlist = nil
end
trials_per_model =
  begin
    Integer(ENV.fetch("OPENROUTER_TRIALS", "1"))
  rescue ArgumentError
    1
  end
trials_per_model = 1 if trials_per_model < 1

verbose_level =
  begin
    Integer(ENV.fetch("VERBOSE", "1"))
  rescue ArgumentError, TypeError
    1
  end
verbose_level = 0 if verbose_level < 0

client_timeout =
  begin
    Float(ENV.fetch("OPENROUTER_CLIENT_TIMEOUT", "120"))
  rescue ArgumentError, TypeError
    120.0
  end
client_timeout = nil if client_timeout <= 0

client_open_timeout =
  begin
    Float(ENV.fetch("OPENROUTER_OPEN_TIMEOUT", "10"))
  rescue ArgumentError, TypeError
    10.0
  end
client_open_timeout = nil if client_open_timeout <= 0

client_read_timeout =
  begin
    raw = ENV.fetch("OPENROUTER_READ_TIMEOUT", "").to_s.strip
    raw.empty? ? nil : Float(raw)
  rescue ArgumentError, TypeError
    nil
  end
client_read_timeout = nil if client_read_timeout && client_read_timeout <= 0
client_read_timeout ||= client_timeout

http_adapter_name = ENV.fetch("OPENROUTER_HTTP_ADAPTER", "httpx").to_s.strip.downcase.tr("-", "_")
http_adapter =
  case http_adapter_name
  when "", "default", "net_http", "nethttp"
    nil
  when "httpx"
    SimpleInference::HTTPAdapters::HTTPX.new(timeout: client_timeout)
  else
    warn "Unknown OPENROUTER_HTTP_ADAPTER=#{http_adapter_name.inspect}. Using httpx."
    http_adapter_name = "httpx"
    SimpleInference::HTTPAdapters::HTTPX.new(timeout: client_timeout)
  end

DEFAULT_MODELS = [
  "deepseek/deepseek-v3.2:nitro",
  "deepseek/deepseek-chat-v3-0324:nitro",
  "x-ai/grok-4.1-fast",
  "google/gemini-2.5-flash:nitro",
  "google/gemini-3-flash-preview:nitro",
  "google/gemini-3-pro-preview:nitro",
  "anthropic/claude-opus-4.5:nitro",
  "openai/gpt-5.2-chat:nitro",
  "openai/gpt-5.2:nitro",
  "minimax/minimax-m2-her",
  "minimax/minimax-m2.1:nitro",
  "qwen/qwen3-vl-30b-a3b-instruct:nitro",
  "qwen/qwen3-next-80b-a3b-instruct:nitro",
  "qwen/qwen3-vl-235b-a22b-instruct:nitro",
  "z-ai/glm-4.7:nitro",
  "z-ai/glm-4.7-flash:nitro",
  "moonshotai/kimi-k2.5:nitro",
].freeze

models = ENV.fetch("OPENROUTER_MODELS", ENV["OPENROUTER_MODEL"].to_s).split(",").map(&:strip).reject(&:empty?)
models = DEFAULT_MODELS if models.empty?

headers = {}
headers["HTTP-Referer"] = ENV["OPENROUTER_HTTP_REFERER"] if ENV["OPENROUTER_HTTP_REFERER"]
headers["X-Title"] = ENV["OPENROUTER_X_TITLE"] if ENV["OPENROUTER_X_TITLE"]

# Optional OpenRouter request-level knobs (OpenAI-compatible).
# These are injected via runtime[:tool_calling][:request_overrides] so the lower
# layers (pipeline/client) stay provider-agnostic.
request_overrides = {}

if (route = ENV["OPENROUTER_ROUTE"].to_s.strip).length.positive?
  request_overrides["route"] = route
end

if (raw = ENV["OPENROUTER_TRANSFORMS"])
  transforms =
    case raw.to_s.strip.downcase
    when "", "auto"
      nil
    when "none", "off", "0", "false"
      []
    else
      raw.split(",").map(&:strip).reject(&:empty?)
    end

  request_overrides["transforms"] = transforms if transforms
end

provider = {}
%w[ONLY ORDER IGNORE].each do |key|
  env_key = "OPENROUTER_PROVIDER_#{key}"
  next unless ENV.key?(env_key)

  raw = ENV[env_key].to_s
  values = raw.split(",").map(&:strip).reject(&:empty?)
  provider[key.downcase] = values if values.any?
end
request_overrides["provider"] = provider if provider.any?

if (raw = ENV["OPENROUTER_REQUEST_OVERRIDES_JSON"].to_s.strip).length.positive?
  begin
    parsed = JSON.parse(raw)
    request_overrides.merge!(parsed) if parsed.is_a?(Hash)
  rescue JSON::ParserError
    warn "Invalid OPENROUTER_REQUEST_OVERRIDES_JSON (must be a JSON object). Ignoring."
  end
end

# Stabilize eval runs across models: prefer sequential tool calls unless a
# scenario opts in (e.g. multi-tool call cases).
if tools_enabled && !request_overrides.key?("parallel_tool_calls")
  request_overrides["parallel_tool_calls"] = false
end

module ToolCallEval
  class Workspace
    attr_reader :id, :facts, :draft, :locks, :ui_state

    def initialize(id: nil, facts: nil, draft: nil, locks: nil, ui_state: nil)
      @id = (id || SecureRandom.uuid).to_s
      @facts = facts.is_a?(Hash) ? deep_dup(facts) : {}
      @draft = draft.is_a?(Hash) ? deep_dup(draft) : {}
      @locks = Array(locks).map(&:to_s)
      @ui_state = ui_state.is_a?(Hash) ? deep_dup(ui_state) : {}
      @facts_version = 0
      @draft_version = 0
    end

    def facts_etag = "facts:#{@facts_version}"
    def draft_etag = "draft:#{@draft_version}"

    def snapshot(select: nil)
      full = {
        "facts" => deep_dup(@facts),
        "draft" => deep_dup(@draft),
        "locks" => { "paths" => @locks.dup },
        "ui_state" => deep_dup(@ui_state),
        "versions" => { "facts_etag" => facts_etag, "draft_etag" => draft_etag },
      }

      paths = Array(select).map(&:to_s).reject(&:empty?)
      return full if paths.empty?

      paths.each_with_object({}) do |pointer, out|
        out[pointer] = read_pointer(full, pointer)
      rescue ArgumentError
        out[pointer] = nil
      end
    end

    def patch_draft!(ops, etag: nil)
      raise ArgumentError, "etag mismatch" if etag && etag.to_s != draft_etag

      applied = 0
      before = deep_dup(@draft)

      begin
        Array(ops).each do |op|
          op = op.is_a?(Hash) ? op : {}

          action = op["op"].to_s
          path = op["path"].to_s
          value = op.key?("value") ? op["value"] : nil
          index = op["index"]

          raise ArgumentError, "path must start with /draft/" unless path.start_with?("/draft/")

          case action
          when "set"
            write_pointer!(@draft, path.delete_prefix("/draft"), value)
            applied += 1
          when "delete"
            delete_pointer!(@draft, path.delete_prefix("/draft"))
            applied += 1
          when "append"
            append_pointer!(@draft, path.delete_prefix("/draft"), value)
            applied += 1
          when "insert"
            insert_pointer!(@draft, path.delete_prefix("/draft"), index, value)
            applied += 1
          else
            raise ArgumentError, "unknown op: #{action.inspect}"
          end
        end
      rescue StandardError
        # Patch operations are atomic: roll back on any failure.
        @draft = before
        raise
      end

      @draft_version += 1 if applied.positive?

      { "draft_etag" => draft_etag, "applied" => applied }
    end

    private

    # Very small JSON Pointer helpers (enough for eval).
    def read_pointer(doc, pointer)
      raise ArgumentError, "pointer must start with /" unless pointer.to_s.start_with?("/")

      tokens = pointer.split("/").drop(1).map { |t| unescape_pointer_token(t) }
      tokens.reduce(doc) do |cur, tok|
        case cur
        when Hash
          cur.fetch(tok)
        when Array
          cur.fetch(Integer(tok))
        else
          raise ArgumentError, "cannot descend into #{cur.class}"
        end
      end
    end

    def write_pointer!(doc, pointer, value)
      pointer = pointer.to_s
      return doc.replace(value) if pointer.empty? || pointer == "/"

      raise ArgumentError, "pointer must start with /" unless pointer.start_with?("/")

      tokens = pointer.split("/").drop(1).map { |t| unescape_pointer_token(t) }
      last = tokens.pop
      parent = tokens.reduce(doc) { |cur, tok| descend_write!(cur, tok) }

      case parent
      when Hash
        parent[last] = value
      when Array
        parent[Integer(last)] = value
      else
        raise ArgumentError, "cannot write into #{parent.class}"
      end
    end

    def delete_pointer!(doc, pointer)
      raise ArgumentError, "pointer must start with /" unless pointer.to_s.start_with?("/")

      tokens = pointer.split("/").drop(1).map { |t| unescape_pointer_token(t) }
      last = tokens.pop
      parent = tokens.reduce(doc) { |cur, tok| descend_write!(cur, tok) }

      case parent
      when Hash
        parent.delete(last)
      when Array
        parent.delete_at(Integer(last))
      else
        raise ArgumentError, "cannot delete from #{parent.class}"
      end
    end

    def append_pointer!(doc, pointer, value)
      arr = read_pointer(doc, pointer)
      raise ArgumentError, "target is not an Array" unless arr.is_a?(Array)

      arr << value
    rescue KeyError
      write_pointer!(doc, pointer, [value])
    end

    def insert_pointer!(doc, pointer, index, value)
      arr = read_pointer(doc, pointer)
      raise ArgumentError, "target is not an Array" unless arr.is_a?(Array)

      i = Integer(index)
      arr.insert(i, value)
    rescue KeyError
      write_pointer!(doc, pointer, [value])
    end

    def descend_write!(cur, tok)
      case cur
      when Hash
        cur[tok] ||= {}
        cur[tok]
      when Array
        idx = Integer(tok)
        cur[idx] ||= {}
        cur[idx]
      else
        raise ArgumentError, "cannot descend into #{cur.class}"
      end
    end

    def unescape_pointer_token(token)
      token.to_s.gsub("~1", "/").gsub("~0", "~")
    end

    def deep_dup(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(k, v), out|
          kk = k.is_a?(String) ? k.dup : k
          out[kk] = deep_dup(v)
        end
      when Array
        obj.map { |v| deep_dup(v) }
      when String
        obj.dup
      else
        obj.dup
      end
    rescue TypeError
      obj
    end
  end

  class Executor
    # Keep the patch surface tiny for cross-model reliability in eval.
    MODEL_ALLOWED_STATE_PATCH_PATHS = ["/draft/foo"].freeze

    def initialize(workspace:)
      @workspace = workspace
    end

    def call(name:, args:)
      args = args.is_a?(Hash) ? args : {}

      workspace_id = args["workspace_id"].to_s
      # For eval robustness across models, treat missing/placeholder IDs as implicit.
      workspace_id = @workspace.id if workspace_id.empty? || workspace_id == "workspace_id"

      if workspace_id != @workspace.id
        return error_envelope(name, code: "WORKSPACE_NOT_FOUND", message: "Unknown workspace_id: #{workspace_id}")
      end

      case name
      when "state_get"
        ok_envelope(name, "snapshot" => @workspace.snapshot(select: args["select"]))
      when "state_patch"
        ops = args["ops"]
        unless ops.is_a?(Array) && ops.any?
          return error_envelope(name, code: "ARGUMENT_ERROR", message: "ops must be a non-empty Array")
        end

        unless model_allowed_state_patch_ops?(ops)
          return error_envelope(
            name,
            code: "ARGUMENT_ERROR",
            message: "Only set on #{MODEL_ALLOWED_STATE_PATCH_PATHS.join(", ")} is allowed",
          )
        end

        result = @workspace.patch_draft!(ops, etag: nil)
        ok_envelope(name, result)
      else
        error_envelope(name, code: "TOOL_NOT_IMPLEMENTED", message: "Tool not implemented: #{name}")
      end
    rescue ArgumentError => e
      error_envelope(name, code: "ARGUMENT_ERROR", message: e.message)
    rescue StandardError => e
      error_envelope(name, code: "INTERNAL_ERROR", message: "#{e.class}: #{e.message}")
    end

    private

    def ok_envelope(name, data)
      {
        "ok" => true,
        "tool_name" => name,
        "data" => data.is_a?(Hash) ? data : { "value" => data },
        "warnings" => [],
        "errors" => [],
      }
    end

    def error_envelope(name, code:, message:)
      {
        "ok" => false,
        "tool_name" => name,
        "data" => {},
        "warnings" => [],
        "errors" => [{ "code" => code, "message" => message.to_s }],
      }
    end

    def model_allowed_state_patch_ops?(ops)
      ops.all? do |op|
        op.is_a?(Hash) &&
          op["op"].to_s == "set" &&
          MODEL_ALLOWED_STATE_PATCH_PATHS.include?(op["path"].to_s)
      end
    end
  end

  def self.tool_definitions
    [
      TavernKit::VibeTavern::ToolCalling::ToolDefinition.new(
        name: "state_get",
        description: "Read workspace state (facts/draft/locks/ui_state/versions).",
        parameters: {
          type: "object",
          additionalProperties: false,
          properties: {
            workspace_id: { type: "string" },
            select: { type: "array", items: { type: "string" } },
          },
          required: [],
        },
      ),
      TavernKit::VibeTavern::ToolCalling::ToolDefinition.new(
        name: "state_patch",
        description: "Apply patch operations to draft state (set/delete/append/insert).",
        parameters: {
          type: "object",
          additionalProperties: false,
          properties: {
            workspace_id: { type: "string" },
            request_id: { type: "string" },
            ops: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                properties: {
                  op: { type: "string" },
                  path: { type: "string" },
                  value: {},
                  index: { type: "integer" },
                },
                required: ["op", "path"],
              },
            },
          },
          required: ["request_id", "ops"],
        },
      ),
      # Include but hide (regression guard): model should never see it.
      TavernKit::VibeTavern::ToolCalling::ToolDefinition.new(
        name: "facts_commit",
        description: "Commit a facts proposal (must be triggered by UI/user confirmation).",
        exposed_to_model: false,
        parameters: {
          type: "object",
          additionalProperties: false,
          properties: {
            workspace_id: { type: "string" },
            request_id: { type: "string" },
            proposal_id: { type: "string" },
            user_confirmed: { type: "boolean" },
          },
          required: ["workspace_id", "request_id", "proposal_id", "user_confirmed"],
        },
      ),
    ]
  end
end

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
  return "TIMEOUT" if msg.include?("TimeoutError") || msg.include?("Net::ReadTimeout") || msg.match?(/Timed out after/i)

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

def normalize_tool_use_mode(value)
  s = value.to_s.strip.downcase.tr("-", "_")

  case s
  when "enforced", "required", "must"
    "enforced"
  when "relaxed", "preferred", "optional"
    "relaxed"
  when "disabled", "off", "none", "0", "false"
    "disabled"
  else
    s.empty? ? "relaxed" : s
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

chat_only_scenario = {
  id: "chat_only",
  title: "Tool calling disabled (control)",
  runtime_overrides: { tool_use_mode: :disabled },
  prepare: ->(_workspace) { },
  system: <<~SYS.strip,
    Tool calling is disabled for this run.
    Do not call any tools.
    Reply with a single sentence: "Done."
  SYS
  user_text: ->(_workspace) { "hello" },
  assert: lambda { |assistant_text:, **|
    assistant_text.to_s.strip == "Done." ? [] : [%(assistant_text != "Done.")]
  },
}.freeze

SCENARIOS =
  if tools_enabled
    [
      {
        id: "happy_path",
        title: "Happy path (get -> patch -> done)",
        runtime_overrides: {},
        prepare: ->(_workspace) { },
        system: <<~SYS.strip,
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
        user_text: ->(workspace) { "workspace_id=#{workspace.id}" },
        assert: lambda { |assistant_text:, workspace:, tools_enabled:, **|
          reasons = []
          reasons << %(assistant_text != "Done.") unless assistant_text.to_s.strip == "Done."
          reasons << %(draft["foo"] != "bar") if tools_enabled && workspace.draft["foo"] != "bar"
          reasons
        },
      },
      {
        id: "partial_success_failure",
        title: "Partial success (state_get ok) + failure (bad state_patch) + recovery",
        runtime_overrides: { request_overrides: { parallel_tool_calls: true } },
        prepare: ->(_workspace) { },
        system: <<~SYS.strip,
          You are a tool-using assistant.
          Rules:
          - In your FIRST assistant response, call BOTH tools in a single message:
            1) `state_get` (valid arguments)
            2) `state_patch` BUT intentionally use an INVALID path (NOT /draft/foo) so it returns ok=false with ARGUMENT_ERROR.
          - After you receive tool results, call `state_patch` again with the CORRECT arguments to set `/draft/foo` to "bar".
          - IMPORTANT: Call at most ONE tool per assistant message after the first response.
          - After a successful `state_patch`, reply with a single sentence: "Done."
        SYS
        user_text: ->(workspace) { "workspace_id=#{workspace.id}" },
        assert: lambda { |assistant_text:, workspace:, tools_enabled:, trace:, **|
          reasons = []
          reasons << %(assistant_text != "Done.") unless assistant_text.to_s.strip == "Done."
          reasons << %(draft["foo"] != "bar") if tools_enabled && workspace.draft["foo"] != "bar"

          saw_mixed =
            Array(trace).any? do |t|
              t.is_a?(Hash) &&
                Array(t[:tool_results]).any? { |r| r.is_a?(Hash) && r[:name].to_s == "state_get" && r[:ok] == true } &&
                Array(t[:tool_results]).any? { |r| r.is_a?(Hash) && r[:name].to_s == "state_patch" && r[:ok] == false }
            end
          reasons << "expected at least one turn with mixed tool results (ok + fail)" if tools_enabled && !saw_mixed

          reasons
        },
      },
      {
        id: "missing_workspace_id",
        title: "Missing workspace_id (implicit context)",
        runtime_overrides: {},
        prepare: ->(_workspace) { },
        system: <<~SYS.strip,
          You are a tool-using assistant.
          Rules:
          - Always call `state_get` first, but DO NOT pass `workspace_id` in its arguments.
          - IMPORTANT: Call at most ONE tool per assistant message. Do NOT call multiple tools in a single response.
          - Then call `state_patch` to set `/draft/foo` to string value "bar".
            - Do NOT pass `workspace_id` in tool arguments.
            - Only change the `/draft/foo` path. Do not change other draft keys.
          - If a tool returns ok=false, read `errors[]`, fix your arguments, and call the tool again.
          - After tools are done, reply with a single sentence: "Done."

          Examples (JSON args):
          - state_get: {}
          - state_patch: {"request_id":"r1","ops":[{"op":"set","path":"/draft/foo","value":"bar"}]}
        SYS
        user_text: ->(workspace) { "workspace_id=#{workspace.id}" },
        assert: lambda { |assistant_text:, workspace:, tools_enabled:, **|
          reasons = []
          reasons << %(assistant_text != "Done.") unless assistant_text.to_s.strip == "Done."
          reasons << %(draft["foo"] != "bar") if tools_enabled && workspace.draft["foo"] != "bar"
          reasons
        },
      },
      {
        id: "type_error_recovery",
        title: "Type error recovery (ops must be Array)",
        runtime_overrides: {},
        prepare: ->(_workspace) { },
        system: <<~SYS.strip,
          You are a tool-using assistant.
          Rules:
          - Always call `state_get` first.
          - IMPORTANT: Call at most ONE tool per assistant message.
          - Then call `state_patch` to set `/draft/foo` to string value "bar".
            - Note: `ops` MUST be an Array; if you send the wrong type, the tool will return ok=false with ARGUMENT_ERROR.
          - If a tool returns ok=false, read `errors[]`, fix your arguments, and call the tool again.
          - Do NOT reply "Done." until AFTER you have received a successful (ok=true) tool result for `state_patch`.
          - After tools are done, reply with a single sentence: "Done."
        SYS
        user_text: ->(workspace) { "workspace_id=#{workspace.id}" },
        assert: lambda { |assistant_text:, workspace:, tools_enabled:, **|
          reasons = []
          reasons << %(assistant_text != "Done.") unless assistant_text.to_s.strip == "Done."
          reasons << %(draft["foo"] != "bar") if tools_enabled && workspace.draft["foo"] != "bar"
          reasons
        },
      },
      {
        id: "happy_path_parallel",
        title: "Happy path (parallel tool calls: state_get + state_patch -> done)",
        runtime_overrides: { request_overrides: { parallel_tool_calls: true } },
        prepare: ->(_workspace) { },
        system: <<~SYS.strip,
          You are a tool-using assistant.
          Rules:
          - In your FIRST assistant response, call BOTH tools in a single message:
            1) `state_get`
            2) `state_patch` (set `/draft/foo` to string value "bar")
          - After tools are done, reply with a single sentence: "Done."
        SYS
        user_text: ->(workspace) { "workspace_id=#{workspace.id}" },
        assert: lambda { |assistant_text:, workspace:, tools_enabled:, trace:, **|
          reasons = []
          reasons << %(assistant_text != "Done.") unless assistant_text.to_s.strip == "Done."
          reasons << %(draft["foo"] != "bar") if tools_enabled && workspace.draft["foo"] != "bar"

          multi =
            Array(trace).any? do |t|
              t.is_a?(Hash) && Array(t[:tool_calls]).size >= 2
            end
          reasons << "expected >=2 tool calls in a single assistant response" if tools_enabled && !multi

          reasons
        },
      },
      {
        id: "long_arguments_guard",
        title: "Long arguments guardrail (ARGUMENTS_TOO_LARGE) + recovery",
        runtime_overrides: { max_tool_args_bytes: 1_500 },
        prepare: ->(_workspace) { },
        system: <<~SYS.strip,
          You are a tool-using assistant.
          Rules:
          - Always call `state_get` first.
          - Then call `state_patch` to set `/draft/foo` to a string value.
            - IMPORTANT: First, try a LONG value (>= 2500 'x' characters).
            - If the tool returns ok=false with ARGUMENTS_TOO_LARGE, retry with the short value "bar".
          - After a successful `state_patch`, reply with a single sentence: "Done."
        SYS
        user_text: ->(workspace) { "workspace_id=#{workspace.id}" },
        assert: lambda { |assistant_text:, workspace:, tools_enabled:, **|
          reasons = []
          reasons << %(assistant_text != "Done.") unless assistant_text.to_s.strip == "Done."
          reasons << %(draft["foo"] != "bar") if tools_enabled && workspace.draft["foo"] != "bar"
          reasons
        },
      },
      {
        id: "tool_output_truncation",
        title: "Tool output too large truncation (TOOL_OUTPUT_TOO_LARGE)",
        runtime_overrides: { max_tool_output_bytes: 5_000, tool_failure_policy: :tolerated },
        prepare: lambda { |workspace|
          workspace.draft["big"] = "x" * 12_000
        },
        system: <<~SYS.strip,
          You are a tool-using assistant.
          Rules:
          - Always call `state_get` first.
          - If the `state_get` tool result returns ok=false with TOOL_OUTPUT_TOO_LARGE, do NOT retry state_get.
            Proceed to call `state_patch` anyway.
          - Then call `state_patch` to set `/draft/foo` to string value "bar".
          - After tools are done, reply with a single sentence: "Done."
        SYS
        user_text: ->(workspace) { "workspace_id=#{workspace.id}" },
        assert: lambda { |assistant_text:, workspace:, tools_enabled:, raw_history:, **|
          reasons = []
          reasons << %(assistant_text != "Done.") unless assistant_text.to_s.strip == "Done."
          reasons << %(draft["foo"] != "bar") if tools_enabled && workspace.draft["foo"] != "bar"

          saw_truncation =
            Array(raw_history).any? do |m|
              next false unless m.respond_to?(:role) && m.respond_to?(:content)
              next false unless m.role.to_s == "tool"

              m.content.to_s.include?("TOOL_OUTPUT_TOO_LARGE")
            end
          reasons << "expected TOOL_OUTPUT_TOO_LARGE to be emitted at least once" unless saw_truncation

          reasons
        },
      },
      chat_only_scenario,
    ]
  else
    [
      chat_only_scenario,
    ]
  end

default_scenario_ids =
  if tools_enabled
    %w[
      happy_path
      missing_workspace_id
      type_error_recovery
      long_arguments_guard
      chat_only
    ]
  else
    %w[chat_only]
  end

raw_requested_scenarios = ENV.fetch("OPENROUTER_SCENARIOS", "").to_s
requested_scenario_tokens =
  raw_requested_scenarios
    .split(",")
    .map(&:strip)
    .reject(&:empty?)

requested_scenarios =
  if requested_scenario_tokens.any? { |v| %w[all full *].include?(v.downcase) }
    nil
  elsif requested_scenario_tokens.empty?
    default_scenario_ids
  else
    expanded =
      requested_scenario_tokens.flat_map do |tok|
        case tok.downcase
        when "default", "smoke"
          default_scenario_ids
        else
          tok
        end
      end

    expanded.map(&:to_s).map(&:strip).reject(&:empty?).uniq
  end

scenarios =
  if requested_scenarios
    SCENARIOS.select { |s| requested_scenarios.include?(s[:id]) }
  else
    SCENARIOS
  end

if scenarios.empty?
  warn(
    "No scenarios selected from OPENROUTER_SCENARIOS=#{raw_requested_scenarios.inspect}. " \
    "Falling back to default: #{default_scenario_ids.join(", ")}",
  )

  scenarios = SCENARIOS.select { |s| default_scenario_ids.include?(s[:id]) }
end

if scenarios.empty?
  warn "No scenarios selected. Available: #{SCENARIOS.map { |s| s[:id] }.join(", ")}"
  exit 2
end

timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
out_dir = Rails.root.join("tmp", "llm_tool_call_eval_reports", timestamp)
FileUtils.mkdir_p(out_dir)

reports = []

models.each_with_index do |model, model_index|
  model_idx = model_index + 1
  model_total = models.length

  client = SimpleInference::Client.new(
    base_url: base_url,
    api_key: api_key,
    headers: headers,
    api_prefix: api_prefix,
    timeout: client_timeout,
    open_timeout: client_open_timeout,
    read_timeout: client_read_timeout,
    adapter: http_adapter,
  )

  safe_model = model.gsub(%r{[^a-zA-Z0-9_.-]+}, "__")

  runs = []
  failures = []

  trials_per_model.times do |trial_idx|
    scenarios.each_with_index do |scenario, scenario_index|
      scenario_idx = scenario_index + 1
      scenario_total = scenarios.length
      scenario_id = scenario.fetch(:id).to_s
      safe_scenario = scenario_id.gsub(%r{[^a-zA-Z0-9_.-]+}, "__")

      $stderr.puts(
        "[#{model_idx}/#{model_total}] [#{scenario_idx}/#{scenario_total}] testing #{model} scenario=#{scenario_id} (trial #{trial_idx + 1}/#{trials_per_model})...",
      )
      $stderr.flush

      workspace = ToolCallEval::Workspace.new
      scenario[:prepare].call(workspace) if scenario[:prepare]

      tool_executor = ToolCallEval::Executor.new(workspace: workspace)
      registry =
        TavernKit::VibeTavern::ToolCalling::ToolRegistry.new(
          definitions: ToolCallEval.tool_definitions,
        )

      tool_calling =
        TavernKit::VibeTavern::ToolCalling::Presets.merge(
          TavernKit::VibeTavern::ToolCalling::Presets.default_tool_calling,
          TavernKit::VibeTavern::ToolCalling::Presets.tool_calling(
            tool_use_mode: tool_use_mode,
            tool_failure_policy: tool_failure_policy,
            fallback_retry_count: fallback_retry_count,
            fix_empty_final: fix_empty_final,
            tool_allowlist: tool_allowlist,
            request_overrides: request_overrides,
          ),
          TavernKit::VibeTavern::ToolCalling::Presets.model_defaults(model),
          scenario[:runtime_overrides] || {},
        )

      effective_tool_use_mode = normalize_tool_use_mode(tool_calling.fetch(:tool_use_mode, tool_use_mode))
      effective_tools_enabled = effective_tool_use_mode != "disabled"

      runtime =
        TavernKit::Runtime::Base.build(
          {
            tool_calling: tool_calling,
          },
          type: :app,
        )

      runner =
        TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(
          client: client,
          model: model,
          tool_executor: tool_executor,
          runtime: runtime,
          registry: registry,
          system: scenario.fetch(:system).to_s,
          strict: false,
        )

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      ok = true
      error = nil
      error_hint = nil
      error_status = nil
      error_body = nil
      error_raw_body = nil
      assistant_text = nil
      trace = nil
      raw_history = nil

      begin
        user_text = scenario.fetch(:user_text).call(workspace).to_s
        progress_printer =
          if verbose_level <= 0
            nil
          else
            heartbeat_thread = nil
            heartbeat_stop = nil

            stop_heartbeat =
              lambda do
                heartbeat_stop&.call
                heartbeat_stop = nil

                t = heartbeat_thread
                heartbeat_thread = nil
                return unless t

                t.wakeup rescue nil
                t.join(0.2)
                t.kill
                t.join(0.1)
              rescue StandardError
                nil
              end

            lambda do |raw_event|
              event = raw_event.is_a?(Hash) ? raw_event : {}
              type = event.fetch(:type, "").to_s
              turn = event.fetch(:turn, nil)

              case type
              when "llm_request_start"
                stop_heartbeat.call

                heartbeat_turn = turn
                heartbeat_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                stop = false
                heartbeat_stop = -> { stop = true }
                heartbeat_thread =
                  Thread.new do
                    after_s = 15.0
                    every_s = 15.0
                    last_print_s = 0.0

                    loop do
                      break if stop

                      sleep 0.5
                      break if stop

                      elapsed_s = Process.clock_gettime(Process::CLOCK_MONOTONIC) - heartbeat_started
                      next if elapsed_s < after_s
                      next if (elapsed_s - last_print_s) < every_s

                      last_print_s = elapsed_s
                      $stderr.puts("  [t#{heartbeat_turn}] .. waiting for llm (#{elapsed_s.round}s)")
                      $stderr.flush
                    end
                  rescue StandardError
                    nil
                  end

                tools_on = event[:tools_enabled] == true
                msg = "  [t#{turn}] -> llm (tools=#{tools_on ? "on" : "off"})"
                if verbose_level >= 2
                  msg << " msgs=#{event[:messages_count]}"
                  msg << " tools=#{event[:tools_count]}"
                  msg << " choice=#{event[:tool_choice] || "auto"}"
                  if event[:request_attempts_left].to_i.positive?
                    msg << " retries_left=#{event[:request_attempts_left]}"
                  end
                end
                $stderr.puts(msg)
              when "llm_request_error"
                stop_heartbeat.call

                msg = "  [t#{turn}] !! llm error"
                msg << " status=#{event[:status]}" if event[:status]
                msg << " #{event[:elapsed_ms]}ms" if verbose_level >= 2 && event[:elapsed_ms]
                msg << " #{truncate(event[:message].to_s, max_chars: 220)}" unless event[:message].to_s.strip.empty?
                $stderr.puts(msg)
              when "llm_request_retry"
                stop_heartbeat.call

                $stderr.puts(
                  "  [t#{turn}] .. retry (tools=off, attempts_left=#{event[:request_attempts_left]})",
                )
              when "llm_request_end"
                stop_heartbeat.call

                ms = event[:elapsed_ms]
                finish = event[:finish_reason]
                tool_calls = Array(event[:tool_calls]).select { |v| v.is_a?(Hash) }
                names = tool_calls.map { |tc| tc.fetch(:name, nil) }.map(&:to_s).map(&:strip).reject(&:empty?).uniq

                msg = "  [t#{turn}] <- llm"
                msg << " #{ms}ms" if ms
                msg << " finish=#{finish}" if finish
                msg << " tool_calls=#{names.join(",")}" if names.any?
                $stderr.puts(msg)
              when "tool_call_start"
                msg = "  [t#{turn}] -> tool #{event[:name]}"
                msg << " args=#{event[:arguments_bytes]}B" if verbose_level >= 2
                if (parse = event[:parse_status]) && parse.to_s != "ok"
                  msg << " parse=#{parse}"
                end
                $stderr.puts(msg)
              when "tool_call_end"
                msg = "  [t#{turn}] <- tool #{event[:name]} ok=#{event[:ok]}"
                msg << " #{event[:elapsed_ms]}ms" if event[:elapsed_ms]
                errors = Array(event[:error_codes]).map(&:to_s).map(&:strip).reject(&:empty?)
                msg << " errors=#{errors.join(",")}" if errors.any?
                if verbose_level >= 2
                  msg << " out=#{event[:output_bytes]}B"
                  msg << " replaced" if event[:output_replaced] == true
                end
                $stderr.puts(msg)
              when "fix_empty_final"
                $stderr.puts(
                  "  [t#{turn}] .. empty final; retry finalization (disable_tools=#{event[:disable_tools]})",
                )
              when "final"
                stop_heartbeat.call
                $stderr.puts("  [t#{turn}] <- final")
              end

              $stderr.flush
            rescue StandardError
              nil
            end
          end

        result = runner.run(user_text: user_text, on_event: progress_printer)

        assistant_text = result[:assistant_text]
        trace = result[:trace]
        raw_history = Array(result[:history])

        fail_reasons =
          Array(
              scenario.fetch(:assert).call(
                assistant_text: assistant_text,
                workspace: workspace,
                tools_enabled: effective_tools_enabled,
                trace: trace,
                raw_history: raw_history,
              )
            )

          unless fail_reasons.empty?
            tool_calls_seen =
              effective_tools_enabled &&
                Array(trace).any? { |t| t.is_a?(Hash) && t.dig(:response_summary, :has_tool_calls) == true }

            if effective_tools_enabled && !tool_calls_seen
              error = "NO_TOOL_CALLS: assistant did not request any tool calls"
            else
              error = "ASSERTION_FAILED: #{fail_reasons.join("; ")}"
            end
            ok = false
          end
      rescue TavernKit::VibeTavern::ToolCalling::ToolLoopRunner::ToolUseError => e
        ok = false
        error = "#{e.code}: #{e.message}"
        trace = e.details.is_a?(Hash) ? e.details.fetch(:trace, nil) : nil
        raw_history = e.details.is_a?(Hash) ? Array(e.details.fetch(:history, nil)) : nil
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
        scenario: scenario_id,
        trial: trial_idx + 1,
        ok: ok,
        elapsed_ms: elapsed_ms,
        tool_use_mode: effective_tool_use_mode,
        tools_enabled: effective_tools_enabled,
        runtime_tool_calling: tool_calling,
        assistant_text: assistant_text,
        draft: workspace.draft,
        error: error,
        error_status: error_status,
        error_body: error_body,
        error_raw_body: error_raw_body,
        error_category: ok ? nil : error_category(error, status: error_status),
        history:
          raw_history&.map do |m|
            if m.respond_to?(:to_serializable_hash)
              m.to_serializable_hash
            else
              { role: m.respond_to?(:role) ? m.role : nil, content: m.respond_to?(:content) ? m.content : m.to_s }
            end
          end,
        trace: trace,
      }

      error_hint = provider_error_hint(report)
      report[:error_hint] = error_hint if error_hint

      file_name = "#{safe_model}__#{safe_scenario}__trial_#{format("%02d", trial_idx + 1)}.json"
      report_path = out_dir.join(file_name)
      File.write(report_path, JSON.pretty_generate(report))

      run_meta = {
        model: model,
        scenario: scenario_id,
        trial: trial_idx + 1,
        ok: ok,
        elapsed_ms: elapsed_ms,
        error: error,
        error_hint: error_hint,
        error_status: error_status,
        error_category: report[:error_category],
        report_path: report_path.relative_path_from(Rails.root).to_s,
      }

      runs << run_meta
      failures << run_meta unless ok

      status_str = ok ? "OK" : "FAIL"
      $stderr.puts(
        "[#{model_idx}/#{model_total}] [#{scenario_idx}/#{scenario_total}] #{status_str} #{model} scenario=#{scenario_id} (trial #{trial_idx + 1}/#{trials_per_model}, #{elapsed_ms}ms)",
      )
      $stderr.flush
    end
  end

  ok_count = runs.count { |t| t[:ok] }
  rate = ok_count.fdiv(runs.size)
  elapsed = runs.map { |t| t[:elapsed_ms].to_i }.sort
  p50 = elapsed[(elapsed.size * 0.50).floor] || 0
  p95 = elapsed[(elapsed.size * 0.95).floor] || 0

  # Keep a small set of failure samples for quick debugging.
  failure_samples = failures.first(3)

  reports << {
    model: model,
    runs: runs.size,
    ok: ok_count,
    ok_rate: rate,
    ms_p50: p50,
    ms_p95: p95,
    scenarios: scenarios.map { |s| s[:id] },
    run_results: runs,
    failure_samples: failure_samples,
  }
end

summary = {
  ts: Time.now.utc.iso8601,
  base_url: base_url,
  api_prefix: api_prefix,
  http_adapter: http_adapter_name,
  client_timeout: client_timeout,
  client_open_timeout: client_open_timeout,
  client_read_timeout: client_read_timeout,
  fix_empty_final: fix_empty_final,
  tool_use_mode: tool_use_mode,
  tool_failure_policy: tool_failure_policy,
  tool_calling_fallback_retry_count: fallback_retry_count,
  tool_allowlist: tool_allowlist,
  request_overrides: request_overrides,
  trials_per_model: trials_per_model,
  scenarios: scenarios.map { |s| s[:id] },
  output_dir: out_dir.to_s,
  models: reports,
}

File.write(out_dir.join("summary.json"), JSON.pretty_generate(summary))

successes = reports.sum { |r| r[:ok].to_i }
total_runs = reports.sum { |r| r[:runs].to_i }
failures = total_runs - successes

puts "LLM Tool Call Eval"
puts "ts: #{summary[:ts]}"
puts "base_url: #{base_url}"
puts "api_prefix: #{api_prefix}"
puts "http_adapter: #{http_adapter_name}"
puts "client_timeout: #{client_timeout || "(none)"}"
puts "client_open_timeout: #{client_open_timeout || "(none)"}"
puts "client_read_timeout: #{client_read_timeout || "(none)"}"
puts "tool_use_mode: #{tool_use_mode}"
puts "tool_failure_policy: #{tool_failure_policy}"
puts "tool_calling_fallback_retry_count: #{fallback_retry_count}"
puts "fix_empty_final: #{fix_empty_final}"
puts "tool_allowlist: #{tool_allowlist ? tool_allowlist.join(",") : "(full)"}"
puts "request_overrides: #{request_overrides.any? ? request_overrides.keys.join(",") : "(none)"}"
puts "parallel_tool_calls(default): #{request_overrides.fetch("parallel_tool_calls", "(provider default)")}"
puts "trials_per_model: #{trials_per_model}"
puts "scenarios: #{scenarios.map { |s| s[:id] }.join(",")}"
puts "models: #{reports.size} (runs=#{total_runs}, ok=#{successes}, fail=#{failures})"
puts "full report: #{out_dir.relative_path_from(Rails.root)}"
puts

header = ["model", "runs", "ok", "rate", "p50_ms", "p95_ms", "status", "category", "sample", "error"]
rows =
  reports.map do |r|
    sample = Array(r[:failure_samples]).first
    sample_path = sample ? sample[:report_path].to_s : "-"
    err = sample ? truncate(sample[:error_hint] || sample[:error].to_s, max_chars: 120) : "-"
    [
      r[:model].to_s,
      r[:runs].to_s,
      r[:ok].to_s,
      format("%.0f%%", r[:ok_rate].to_f * 100),
      r[:ms_p50].to_s,
      r[:ms_p95].to_s,
      sample && sample[:error_status] ? sample[:error_status].to_s : "-",
      sample ? (sample[:error_category] || "-") : "-",
      sample_path,
      err,
    ]
  end

widths = header.map.with_index { |h, idx| ([h.length] + rows.map { |row| row[idx].length }).max }

fmt = widths.map { |w| "%-#{w}s" }.join(" | ")
sep = widths.map { |w| "-" * w }.join("-|-")

puts format(fmt, *header)
puts sep
rows.each { |row| puts format(fmt, *row) }
