# frozen_string_literal: true

require_relative "test_helper"

require "securerandom"
require_relative "../../lib/tavern_kit/vibe_tavern/tool_calling/presets"

class ToolCallEvalTestWorkspace
  attr_reader :id, :draft, :ui_state

  def initialize(id: nil, draft: nil)
    @id = (id || SecureRandom.uuid).to_s
    @draft = draft.is_a?(Hash) ? deep_dup(draft) : {}
    @ui_state = {}
  end

  def snapshot(select: nil)
    # For ToolLoopRunner tests we only need a stable, serializable structure.
    {
      "draft" => deep_dup(@draft),
    }
  end

  def patch_draft!(ops, etag: nil)
    applied = 0
    before = deep_dup(@draft)

    begin
      Array(ops).each do |op|
        op = op.is_a?(Hash) ? op : {}

        action = op["op"].to_s
        path = op["path"].to_s
        value = op.key?("value") ? op["value"] : nil

        raise ArgumentError, "path must start with /draft/" unless path.start_with?("/draft/")

        case action
        when "set"
          key = path.delete_prefix("/draft/")
          raise ArgumentError, "invalid path" if key.include?("/")

          @draft[key] = value
          applied += 1
        else
          raise ArgumentError, "unknown op: #{action.inspect}"
        end
      end
    rescue StandardError
      @draft = before
      raise
    end

    { "applied" => applied }
  end

  private

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

class ToolCallEvalTestExecutor
  MODEL_ALLOWED_STATE_PATCH_PATHS = ["/draft/foo"].freeze

  def initialize(workspace:)
    @workspace = workspace
  end

  def call(name:, args:)
    args = args.is_a?(Hash) ? args : {}

    workspace_id = args["workspace_id"].to_s
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

      ok_envelope(name, @workspace.patch_draft!(ops, etag: nil))
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
      ok: true,
      tool_name: name,
      data: data.is_a?(Hash) ? data : { value: data },
      warnings: [],
      errors: [],
    }
  end

  def error_envelope(name, code:, message:)
    {
      ok: false,
      tool_name: name,
      data: {},
      warnings: [],
      errors: [{ code: code, message: message.to_s }],
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

class ToolLoopRunnerTest < Minitest::Test
  def build_registry
    defs = [
      TavernKit::VibeTavern::ToolCalling::ToolDefinition.new(
        name: "state_get",
        description: "Read workspace state",
        parameters: { type: "object", properties: { workspace_id: { type: "string" } } },
      ),
      TavernKit::VibeTavern::ToolCalling::ToolDefinition.new(
        name: "state_patch",
        description: "Patch draft",
        parameters: { type: "object", properties: { workspace_id: { type: "string" } } },
      ),
      TavernKit::VibeTavern::ToolCalling::ToolDefinition.new(
        name: "facts_commit",
        description: "Commit facts (UI only)",
        exposed_to_model: false,
        parameters: { type: "object", properties: { workspace_id: { type: "string" } } },
      ),
    ]

    TavernKit::VibeTavern::ToolCalling::ToolRegistry.new(definitions: defs)
  end

  def build_runner(
    client:,
    model:,
    workspace:,
    registry: build_registry,
    tool_use_mode: nil,
    context: nil,
    parallel_tool_calls: true,
    fix_empty_final: nil,
    tool_calling_fallback_retry_count: nil,
    llm_options_defaults: nil,
    strict: false,
    system: nil
  )
    context_hash =
      case context
      when nil
        {}
      when TavernKit::PromptBuilder::Context
        context.to_h
      when Hash
        context
      else
        raise ArgumentError, "context must be a Hash or TavernKit::PromptBuilder::Context"
      end

    base_tool_calling =
      TavernKit::VibeTavern::ToolCalling::Presets.default_tool_calling

    overrides = {}
    overrides[:tool_use_mode] = tool_use_mode unless tool_use_mode.nil?
    overrides[:fix_empty_final] = fix_empty_final unless fix_empty_final.nil?
    overrides[:fallback_retry_count] = tool_calling_fallback_retry_count unless tool_calling_fallback_retry_count.nil?

    tool_calling =
      TavernKit::VibeTavern::ToolCalling::Presets.merge(
        base_tool_calling,
        context_hash.fetch(:tool_calling, {}),
        overrides,
      )

    if !parallel_tool_calls.nil?
      request_overrides = tool_calling.fetch(:request_overrides, nil)
      request_overrides = {} unless request_overrides.is_a?(Hash)

      unless request_overrides.key?(:parallel_tool_calls)
        tool_calling =
          tool_calling.merge(
            request_overrides: request_overrides.merge(parallel_tool_calls: parallel_tool_calls),
          )
      end
    end

    effective_mode = tool_calling.fetch(:tool_use_mode, :relaxed).to_sym
    tool_executor_obj = effective_mode == :disabled ? nil : ToolCallEvalTestExecutor.new(workspace: workspace)

    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openrouter",
        model: model,
        context: context_hash.merge(tool_calling: tool_calling),
        llm_options_defaults: llm_options_defaults,
      )

    prompt_runner = TavernKit::VibeTavern::PromptRunner.new(client: client)

    TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(
      prompt_runner: prompt_runner,
      runner_config: runner_config,
      tool_executor: tool_executor_obj,
      registry: registry,
      system: system,
      strict: strict,
    )
  end

  def test_tool_loop_executes_tool_calls_and_continues
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                id: "chatcmpl-1",
                object: "chat.completion",
                created: 123,
                model: body["model"],
                choices: [
                  {
                    index: 0,
                    message: {
                      role: "assistant",
                      content: "Calling tools now.",
                      tool_calls: [
                        {
                          id: "call_1",
                          type: "function",
                          function: {
                            name: "state_get",
                            arguments: JSON.generate({ workspace_id: workspace_id }),
                          },
                        },
                        {
                          id: "call_2",
                          type: "function",
                          function: {
                            name: "state_patch",
                            arguments: JSON.generate(
                              {
                                workspace_id: workspace_id,
                                request_id: "r1",
                                ops: [
                                  { op: "set", path: "/draft/foo", value: "bar" },
                                ],
                              }
                            ),
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                id: "chatcmpl-2",
                object: "chat.completion",
                created: 124,
                model: body["model"],
                choices: [
                  {
                    index: 0,
                    message: { role: "assistant", content: "Done." },
                    finish_reason: "stop",
                  },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new

    client =
      SimpleInference::Client.new(
        base_url: "http://example.com",
        api_key: "secret",
        adapter: adapter,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace)

    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    assert_equal "Done.", result[:assistant_text]
    assert_equal "bar", workspace.draft["foo"]

    t0 = result[:trace].find { |t| t[:turn] == 0 }
    refute_nil t0
    assert_equal %w[state_get state_patch], Array(t0[:tool_calls]).map { |tc| tc[:name] }

    assert_equal 2, requests.length

    req1 = JSON.parse(requests[0][:body])
    assert_equal "test-model", req1["model"]
    assert_equal "auto", req1["tool_choice"]
    assert req1["tools"].is_a?(Array)

    tool_names = req1["tools"].map { |t| t.dig("function", "name") }.compact
    assert_includes tool_names, "state_get"
    assert_includes tool_names, "state_patch"
    refute_includes tool_names, "facts_commit"

    req2 = JSON.parse(requests[1][:body])
    msgs2 = req2["messages"]

    user2 = msgs2.find { |m| m["role"] == "user" }
    refute_nil user2
    assert_includes user2["content"].to_s, "workspace_id="

    assistant_with_calls = msgs2.find { |m| m["role"] == "assistant" && m.key?("tool_calls") }
    refute_nil assistant_with_calls
    assert_equal "", assistant_with_calls["content"].to_s

    tool_result = msgs2.find { |m| m["role"] == "tool" && m.key?("tool_call_id") }
    refute_nil tool_result
  end

  def test_tool_loop_emits_progress_events
    requests = []
    events = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_1",
                          type: "function",
                          function: {
                            name: "state_get",
                            arguments: JSON.generate({ workspace_id: workspace_id }),
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            elsif @call_count == 2
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_2",
                          type: "function",
                          function: {
                            name: "state_patch",
                            arguments: JSON.generate(
                              {
                                workspace_id: workspace_id,
                                request_id: "r1",
                                ops: [
                                  { op: "set", path: "/draft/foo", value: "bar" },
                                ],
                              }
                            ),
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace)

    result =
      runner.run(user_text: "workspace_id=#{workspace.id}") do |e|
        events << e
      end

    assert_equal "Done.", result[:assistant_text]
    assert_equal "bar", workspace.draft["foo"]

    types = events.map { |e| e.fetch(:type) }
    assert_includes types, :llm_request_start
    assert_includes types, :llm_request_end
    assert_includes types, :tool_call_start
    assert_includes types, :tool_call_end
    assert_includes types, :final

    tool_end = events.find { |e| e[:type] == :tool_call_end && e[:name].to_s == "state_patch" }
    refute_nil tool_end
    assert_equal true, tool_end[:ok]
    assert tool_end[:elapsed_ms].is_a?(Integer)
    assert tool_end[:output_bytes].is_a?(Integer)
  end

  def test_tool_loop_ignores_on_event_callback_errors
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: "Done." }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace, tool_use_mode: :disabled)

    result = runner.run(user_text: "hello", on_event: ->(_e) { raise "boom" })
    assert_equal "Done.", result[:assistant_text]
  end

  def test_tool_loop_limits_tool_calls_per_turn_when_parallel_tool_calls_disabled
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_1",
                          type: "function",
                          function: { name: "state_get", arguments: JSON.generate({ workspace_id: workspace_id }) },
                        },
                        {
                          id: "call_2",
                          type: "function",
                          function: {
                            name: "state_patch",
                            arguments: JSON.generate(
                              {
                                workspace_id: workspace_id,
                                request_id: "r1",
                                ops: [{ op: "set", path: "/draft/foo", value: "bar" }],
                              }
                            ),
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            elsif @call_count == 2
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_3",
                          type: "function",
                          function: {
                            name: "state_patch",
                            arguments: JSON.generate(
                              {
                                workspace_id: workspace_id,
                                request_id: "r1",
                                ops: [{ op: "set", path: "/draft/foo", value: "bar" }],
                              }
                            ),
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    context = { tool_calling: { request_overrides: { parallel_tool_calls: false } } }
    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)

    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    assert_equal "Done.", result[:assistant_text]
    assert_equal "bar", workspace.draft["foo"]

    t0 = result[:trace].find { |t| t[:turn] == 0 }
    refute_nil t0
    assert_equal 1, t0.dig(:response_summary, :tool_calls_count)
    assert_equal 1, t0.dig(:response_summary, :ignored_tool_calls_count)
    assert_equal ["state_get"], Array(t0[:tool_calls]).map { |tc| tc[:name] }
  end

  def test_tool_loop_includes_usage_in_trace_when_present
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          if @call_count == 1
            response_body = {
              choices: [
                {
                  message: {
                    role: "assistant",
                    content: "",
                    tool_calls: [
                      { id: "call_1", type: "function", function: { name: "state_get", arguments: "{}" } },
                    ],
                  },
                  finish_reason: "tool_calls",
                },
              ],
              usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
            }
          else
            response_body = {
              choices: [
                { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
              ],
              usage: { prompt_tokens: 2, completion_tokens: 1, total_tokens: 3 },
            }
          end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace)

    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    t0 = result[:trace].find { |t| t[:turn] == 0 }
    refute_nil t0
    assert_equal 15, t0.dig(:response_summary, :usage, "total_tokens")
  end

  def test_tool_call_names_with_whitespace_are_stripped
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_1",
                          type: "function",
                          function: {
                            name: "state_get",
                            arguments: JSON.generate({ workspace_id: workspace_id }),
                          },
                        },
                        {
                          id: "call_2",
                          type: "function",
                          function: {
                            name: " state_patch ",
                            arguments: JSON.generate(
                              {
                                workspace_id: workspace_id,
                                request_id: "r1",
                                ops: [
                                  { op: "set", path: "/draft/foo", value: "bar" },
                                ],
                              }
                            ),
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace)

    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    assert_equal "Done.", result[:assistant_text]
    assert_equal "bar", workspace.draft["foo"]

    t0 = result[:trace].find { |t| t[:turn] == 0 }
    tool_names = Array(t0[:tool_calls]).map { |tc| tc[:name] }
    assert_equal %w[state_get state_patch], tool_names
  end

  def test_tool_definition_strips_empty_required_arrays_for_provider_compatibility
    registry =
      TavernKit::VibeTavern::ToolCalling::ToolRegistry.new(
        definitions: [
          TavernKit::VibeTavern::ToolCalling::ToolDefinition.new(
            name: "tool_with_empty_required",
            description: "Test tool",
            parameters: {
              "type" => "object",
              "required" => [],
              "properties" => {
                "nested" => {
                  "type" => "object",
                  "required" => [],
                  "properties" => {},
                },
              },
            },
          ),
        ],
      )

    tool = registry.openai_tools.first
    params = tool.dig(:function, :parameters)

    refute params.key?("required")
    refute params.dig("properties", "nested").key?("required")
  end

  def test_context_request_overrides_are_merged_and_reserved_keys_are_ignored
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: "Done." }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            tool_use_mode: :relaxed,
            request_overrides: {
              temperature: 0.123,
              transforms: ["middle-out"],
              response_format: { type: "json_object" },
              model: "evil-model",
              tool_choice: "none",
              tools: [
                { type: "function", function: { name: "evil_tool", parameters: { type: "object" } } },
              ],
            },
          },
        },
        type: :app,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace, tool_use_mode: :relaxed, context: context)
    runner.run(user_text: "workspace_id=#{workspace.id}")

    req = JSON.parse(requests[0][:body])
    assert_equal "test-model", req["model"]
    assert_equal 0.123, req["temperature"]
    assert_equal ["middle-out"], req["transforms"]

    # request_overrides cannot override tool_choice/tools/model; those are owned by ToolLoopRunner.
    assert_nil req["response_format"]
    assert_equal "auto", req["tool_choice"]
    tool_names = Array(req["tools"]).map { |t| t.dig("function", "name") }.compact
    assert_includes tool_names, "state_get"
    refute_includes tool_names, "evil_tool"
  end

  def test_tool_loop_runner_propagates_prompt_runner_llm_options_defaults
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: "Done." }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    runner =
      build_runner(
        client: client,
        model: "test-model",
        workspace: workspace,
        tool_use_mode: :relaxed,
        llm_options_defaults: { temperature: 0.7 },
      )

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req = JSON.parse(requests[0][:body])
    assert_in_delta 0.7, req.fetch("temperature"), 0.0001
  end

  def test_context_tool_choice_overrides_default
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: "Done." }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            tool_use_mode: :relaxed,
            tool_choice: "none",
          },
        },
        type: :app,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace, tool_use_mode: :relaxed, context: context)
    runner.run(user_text: "workspace_id=#{workspace.id}")

    req = JSON.parse(requests[0][:body])
    assert_equal "none", req["tool_choice"]
  end

  def test_facts_commit_is_not_exposed_to_the_model
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_commit",
                          type: "function",
                          function: {
                            name: "facts_commit",
                            arguments: JSON.generate(
                              {
                                workspace_id: workspace_id,
                                request_id: "r1",
                                proposal_id: "p1",
                                user_confirmed: true,
                              }
                            ),
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  {
                    message: { role: "assistant", content: "Done." },
                    finish_reason: "stop",
                  },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    runner = build_runner(client: client, model: "test-model", workspace: workspace)

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_result = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_result
    assert_includes tool_result["content"], "TOOL_NOT_ALLOWED"
  end

  def test_tool_denylist_hides_tools_from_prompt_and_blocks_execution
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_get",
                          type: "function",
                          function: { name: "state_get", arguments: JSON.generate({ workspace_id: workspace_id }) },
                        },
                        {
                          id: "call_patch",
                          type: "function",
                          function: {
                            name: "state_patch",
                            arguments: JSON.generate(
                              {
                                workspace_id: workspace_id,
                                request_id: "r1",
                                ops: [{ op: "set", path: "/draft/foo", value: "bar" }],
                              }
                            ),
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            tool_use_mode: :relaxed,
            tool_denylist: ["state_patch"],
          },
        },
        type: :app,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace, tool_use_mode: :relaxed, context: context)

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req1 = JSON.parse(requests[0][:body])
    tool_names = Array(req1["tools"]).map { |t| t.dig("function", "name") }.compact
    assert_includes tool_names, "state_get"
    refute_includes tool_names, "state_patch"

    req2 = JSON.parse(requests[1][:body])
    tool_result = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" && m["tool_call_id"] == "call_patch" }
    refute_nil tool_result
    assert_includes tool_result["content"], "TOOL_NOT_ALLOWED"
  end

  def test_system_prompt_is_included_as_a_system_message
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            ),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    runner = build_runner(client: client, model: "test-model", workspace: workspace, system: "SYSTEM INSTRUCTIONS")

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req = JSON.parse(requests[0][:body])
    roles = Array(req["messages"]).map { |m| m["role"] }
    assert_equal "system", roles.first
    assert_equal "SYSTEM INSTRUCTIONS", req["messages"][0]["content"]
  end

  def test_invalid_json_tool_arguments_returns_error_envelope
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_bad_json",
                          type: "function",
                          function: { name: "state_get", arguments: "{" }, # invalid JSON
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace)

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg

    parsed = JSON.parse(tool_msg["content"])
    assert_equal false, parsed["ok"]
    assert_includes parsed.dig("errors", 0, "code"), "ARGUMENTS_JSON_PARSE_ERROR"
  end

  def test_missing_workspace_id_is_treated_as_implicit
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_missing_ws",
                          type: "function",
                          function: { name: "state_get", arguments: JSON.generate({}) },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace)

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg

    parsed = JSON.parse(tool_msg["content"])
    assert_equal true, parsed["ok"]
    assert parsed.dig("data", "snapshot").is_a?(Hash)
  end

  def test_mismatched_workspace_id_returns_workspace_not_found
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_wrong_ws",
                          type: "function",
                          function: { name: "state_get", arguments: JSON.generate({ workspace_id: "not-the-ws" }) },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace)

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg

    parsed = JSON.parse(tool_msg["content"])
    assert_equal false, parsed["ok"]
    assert_includes parsed.dig("errors", 0, "code"), "WORKSPACE_NOT_FOUND"
  end

  def test_state_patch_invalid_path_returns_argument_error
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_bad_path",
                          type: "function",
                          function: {
                            name: "state_patch",
                            arguments: JSON.generate(
                              {
                                workspace_id: workspace_id,
                                request_id: "r1",
                                ops: [
                                  { op: "set", path: "/facts/nope", value: "x" },
                                ],
                              }
                            ),
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace)

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg

    parsed = JSON.parse(tool_msg["content"])
    assert_equal false, parsed["ok"]
    assert_includes parsed.dig("errors", 0, "code"), "ARGUMENT_ERROR"
  end

  def test_state_patch_path_not_allowed_returns_argument_error
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_wrong_path",
                          type: "function",
                          function: {
                            name: "state_patch",
                            arguments: JSON.generate(
                              {
                                workspace_id: workspace_id,
                                request_id: "r1",
                                ops: [{ op: "set", path: "/draft/README.md", value: "bar" }],
                              }
                            ),
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace)

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg

    parsed = JSON.parse(tool_msg["content"])
    assert_equal false, parsed["ok"]
    assert_includes parsed.dig("errors", 0, "code"), "ARGUMENT_ERROR"
  end

  def test_duplicate_tool_call_ids_are_handled
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "dup",
                          type: "function",
                          function: { name: "state_get", arguments: JSON.generate({ workspace_id: workspace_id }) },
                        },
                        {
                          id: "dup",
                          type: "function",
                          function: {
                            name: "state_patch",
                            arguments: JSON.generate(
                              {
                                workspace_id: workspace_id,
                                request_id: "r1",
                                ops: [{ op: "set", path: "/draft/foo", value: "bar" }],
                              }
                            ),
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace)

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_msgs = Array(req2["messages"]).select { |m| m.is_a?(Hash) && m["role"] == "tool" }
    assert_equal 2, tool_msgs.size
    assert_equal ["dup", "dup__2"], tool_msgs.map { |m| m["tool_call_id"] }
  end

  def test_tool_arguments_too_large_returns_error
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          max = TavernKit::VibeTavern::ToolCalling::ToolLoopRunner::MAX_TOOL_ARGS_BYTES
          big = "a" * (max + 1000)

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_big_args",
                          type: "function",
                          function: {
                            name: "state_patch",
                            arguments: JSON.generate({ workspace_id: workspace_id, request_id: "r1", ops: [], pad: big }),
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace)

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg

    parsed = JSON.parse(tool_msg["content"])
    assert_equal false, parsed["ok"]
    assert_includes parsed.dig("errors", 0, "code"), "ARGUMENTS_TOO_LARGE"
  end

  def test_tool_arguments_hash_too_large_returns_error
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          big = "a" * 1_000

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_big_args_hash",
                          type: "function",
                          function: {
                            name: "state_patch",
                            arguments: { workspace_id: workspace_id, request_id: "r1", ops: [], pad: big },
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            max_tool_args_bytes: 200,
          },
        },
        type: :app,
      )

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg

    parsed = JSON.parse(tool_msg["content"])
    assert_equal false, parsed["ok"]
    assert_includes parsed.dig("errors", 0, "code"), "ARGUMENTS_TOO_LARGE"
  end

  def test_tool_output_too_large_is_replaced
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_state_get",
                          type: "function",
                          function: { name: "state_get", arguments: JSON.generate({ workspace_id: workspace_id }) },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    max = TavernKit::VibeTavern::ToolCalling::ToolLoopRunner::MAX_TOOL_OUTPUT_BYTES
    workspace = ToolCallEvalTestWorkspace.new(draft: { "big" => ("x" * (max + 10_000)) })

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace)

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg

    parsed = JSON.parse(tool_msg["content"])
    assert_equal false, parsed["ok"]
    assert_includes parsed.dig("errors", 0, "code"), "TOOL_OUTPUT_TOO_LARGE"
    refute_includes tool_msg["content"], "x" * 1000
  end

  def test_tool_result_transform_is_applied_to_tool_output_too_large_envelope
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_state_get",
                          type: "function",
                          function: { name: "state_get", arguments: JSON.generate({ workspace_id: workspace_id }) },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    max = TavernKit::VibeTavern::ToolCalling::ToolLoopRunner::MAX_TOOL_OUTPUT_BYTES
    workspace = ToolCallEvalTestWorkspace.new(draft: { "big" => ("x" * (max + 10_000)) })

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            tool_result_transforms: ["tool_result_compact_envelope"],
          },
        },
        type: :app,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg

    parsed = JSON.parse(tool_msg["content"])
    assert_equal false, parsed["ok"]
    assert_includes parsed.dig("errors", 0, "code"), "TOOL_OUTPUT_TOO_LARGE"

    # tool_result_compact_envelope should remove empty warning arrays even for
    # error envelopes like TOOL_OUTPUT_TOO_LARGE.
    refute parsed.key?("warnings")
  end

  def test_fix_empty_final_retries
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            case @call_count
            when 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_1",
                          type: "function",
                          function: { name: "state_get", arguments: JSON.generate({ workspace_id: workspace_id }) },
                        },
                        {
                          id: "call_2",
                          type: "function",
                          function: {
                            name: "state_patch",
                            arguments: JSON.generate(
                              {
                                workspace_id: workspace_id,
                                request_id: "r1",
                                ops: [{ op: "set", path: "/draft/foo", value: "bar" }],
                              }
                            ),
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            when 2
              {
                choices: [
                  {
                    message: { role: "assistant", content: "" }, # empty final
                    finish_reason: "stop",
                  },
                ],
              }
            else
              {
                choices: [
                  {
                    message: { role: "assistant", content: "Done." },
                    finish_reason: "stop",
                  },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace, system: "SYSTEM", fix_empty_final: true)

    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    assert_equal "Done.", result[:assistant_text]
    assert_equal "bar", workspace.draft["foo"]

    assert_equal 3, requests.length

    req3 = JSON.parse(requests[2][:body])
    assert_nil req3["tool_choice"]
    assert_nil req3["tools"]

    user_texts3 = Array(req3["messages"]).filter_map { |m| m.is_a?(Hash) && m["role"] == "user" ? m["content"].to_s : nil }
    assert user_texts3.any? { |t| t.include?("Please provide your final answer") }
  end

  def test_fix_empty_final_retry_prompt_can_be_overridden_and_tools_can_be_kept
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            case @call_count
            when 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_1",
                          type: "function",
                          function: { name: "state_get", arguments: JSON.generate({ workspace_id: workspace_id }) },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            when 2
              {
                choices: [
                  {
                    message: { role: "assistant", content: "" }, # empty final
                    finish_reason: "stop",
                  },
                ],
              }
            else
              {
                choices: [
                  {
                    message: { role: "assistant", content: "Done." },
                    finish_reason: "stop",
                  },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            fix_empty_final_user_text: "FINALIZE_IN_ENGLISH",
            fix_empty_final_disable_tools: false,
          },
        },
        type: :app,
      )

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context, fix_empty_final: true)

    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    assert_equal "Done.", result[:assistant_text]

    assert_equal 3, requests.length

    req3 = JSON.parse(requests[2][:body])
    assert_equal "auto", req3["tool_choice"]
    assert req3["tools"].is_a?(Array)

    user_texts3 = Array(req3["messages"]).filter_map { |m| m.is_a?(Hash) && m["role"] == "user" ? m["content"].to_s : nil }
    assert user_texts3.any? { |t| t.include?("FINALIZE_IN_ENGLISH") }
  end

  def test_message_transform_can_inject_reasoning_content_on_assistant_tool_call_messages
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: "Done." }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            message_transforms: ["assistant_tool_calls_reasoning_content_empty_if_missing"],
          },
        },
        type: :app,
      )

    tool_calls = [
      {
        "id" => "call_1",
        "type" => "function",
        "function" => { "name" => "state_get", "arguments" => "{}" },
      },
    ]

    history = [
      TavernKit::PromptBuilder::Message.new(role: :assistant, content: "", metadata: { tool_calls: tool_calls }),
    ]

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)
    runner.run(user_text: "hello", history: history)

    req = JSON.parse(requests[0][:body])
    assistant_tool_msg =
      Array(req["messages"]).find do |m|
        m.is_a?(Hash) && m["role"] == "assistant" && m["tool_calls"].is_a?(Array) && m["tool_calls"].any?
      end

    refute_nil assistant_tool_msg
    assert_equal "", assistant_tool_msg["reasoning_content"]
  end

  def test_message_transform_can_null_out_empty_content_on_assistant_tool_call_messages
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: "Done." }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            message_transforms: ["assistant_tool_calls_content_null_if_blank"],
          },
        },
        type: :app,
      )

    tool_calls = [
      {
        "id" => "call_1",
        "type" => "function",
        "function" => { "name" => "state_get", "arguments" => "{}" },
      },
    ]

    history = [
      TavernKit::PromptBuilder::Message.new(role: :assistant, content: "", metadata: { tool_calls: tool_calls }),
    ]

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)
    runner.run(user_text: "hello", history: history)

    req = JSON.parse(requests[0][:body])
    assistant_tool_msg =
      Array(req["messages"]).find do |m|
        m.is_a?(Hash) && m["role"] == "assistant" && m["tool_calls"].is_a?(Array) && m["tool_calls"].any?
      end

    refute_nil assistant_tool_msg
    assert_nil assistant_tool_msg["content"]
  end

  def test_message_transform_can_inject_signature_on_assistant_tool_calls
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: "Done." }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            message_transforms: ["assistant_tool_calls_signature_skip_validator_if_missing"],
          },
        },
        type: :app,
      )

    tool_calls = [
      {
        "id" => "call_1",
        "type" => "function",
        "function" => { "name" => "state_get", "arguments" => "{}" },
      },
    ]

    history = [
      TavernKit::PromptBuilder::Message.new(role: :assistant, content: "", metadata: { tool_calls: tool_calls }),
    ]

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)
    runner.run(user_text: "hello", history: history)

    req = JSON.parse(requests[0][:body])
    assistant_tool_msg =
      Array(req["messages"]).find do |m|
        m.is_a?(Hash) && m["role"] == "assistant" && m["tool_calls"].is_a?(Array) && m["tool_calls"].any?
      end

    refute_nil assistant_tool_msg
    first_call = Array(assistant_tool_msg["tool_calls"]).first
    assert_equal "skip_thought_signature_validator", first_call["signature"]
  end

  def test_tool_transform_can_modify_tools_before_dispatch
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: "Done." }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            tool_transforms: ["openai_tools_strip_function_descriptions"],
          },
        },
        type: :app,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)
    runner.run(user_text: "hello")

    req = JSON.parse(requests[0][:body])
    first_tool = Array(req["tools"]).find { |t| t.is_a?(Hash) && t.dig("function", "name") == "state_get" }
    refute_nil first_tool
    refute first_tool.fetch("function", {}).key?("description")
  end

  def test_response_transform_can_convert_function_call_to_tool_calls
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      function_call: {
                        name: "state_get",
                        arguments: JSON.generate({ workspace_id: workspace_id }),
                      },
                    },
                    finish_reason: "function_call",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            response_transforms: ["assistant_function_call_to_tool_calls"],
          },
        },
        type: :app,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)
    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    assert_equal "Done.", result[:assistant_text]
    assert_equal 2, requests.length

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg
  end

  def test_response_transform_can_convert_tool_calls_object_to_array
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: {
                        id: "call_1",
                        type: "function",
                        function: {
                          name: "state_get",
                          arguments: JSON.generate({ workspace_id: workspace_id }),
                        },
                      },
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            response_transforms: ["assistant_tool_calls_object_to_array"],
          },
        },
        type: :app,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)
    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    assert_equal "Done.", result[:assistant_text]
    assert_equal 2, requests.length

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg
  end

  def test_runner_handles_tool_calls_object_payload_without_any_transform
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: {
                        id: "call_1",
                        type: "function",
                        function: {
                          name: "state_get",
                          arguments: JSON.generate({ workspace_id: workspace_id }),
                        },
                      },
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    runner = build_runner(client: client, model: "test-model", workspace: workspace)
    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    assert_equal "Done.", result[:assistant_text]
    assert_equal 2, requests.length

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg
  end

  def test_response_transform_can_parse_tool_call_tags_from_assistant_content
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: %(<tool_call>{"name":"state_get","arguments":{"workspace_id":"#{workspace_id}"}}</tool_call>),
                    },
                    finish_reason: "stop",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            response_transforms: ["assistant_content_tool_call_tags_to_tool_calls"],
          },
        },
        type: :app,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)
    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    assert_equal "Done.", result[:assistant_text]
    assert_equal 2, requests.length

    req2 = JSON.parse(requests[1][:body])
    assistant_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "assistant" && m["tool_calls"].is_a?(Array) }
    refute_nil assistant_msg
    assert_equal "", assistant_msg["content"]
  end

  def test_response_transform_ignores_tool_call_tags_inside_fenced_code_blocks
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          raise "unexpected extra request" if @call_count > 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          content = <<~TEXT
            ```txt
            <tool_call>{"name":"state_get","arguments":{"workspace_id":"#{workspace_id}"}}</tool_call>
            ```
          TEXT

          response_body = {
            choices: [
              {
                message: { role: "assistant", content: content },
                finish_reason: "stop",
              },
            ],
          }

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            response_transforms: ["assistant_content_tool_call_tags_to_tool_calls"],
          },
        },
        type: :app,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)
    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    assert_equal 1, requests.length
    assert_includes result[:assistant_text], "<tool_call>"
    assert_match(/```txt/m, result[:assistant_text])
  end

  def test_response_transform_ignores_escaped_tool_call_tags
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          raise "unexpected extra request" if @call_count > 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          content = %Q(\\<tool_call>{"name":"state_get","arguments":{"workspace_id":"#{workspace_id}"}}\\</tool_call>)

          response_body = {
            choices: [
              {
                message: { role: "assistant", content: content },
                finish_reason: "stop",
              },
            ],
          }

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          output_tags: { enabled: false, escape_hatch: { enabled: true, mode: :html_entity } },
          tool_calling: {
            response_transforms: ["assistant_content_tool_call_tags_to_tool_calls"],
          },
        },
        type: :app,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)
    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    assert_equal 1, requests.length
    assert_includes result[:assistant_text], "&lt;tool_call>"
    refute_includes result[:assistant_text], "<tool_call>"
  end

  def test_parse_args_accepts_blank_string_and_json_code_fence
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_get_blank",
                          type: "function",
                          function: {
                            name: "state_get",
                            arguments: "   ",
                          },
                        },
                        {
                          id: "call_patch_fenced",
                          type: "function",
                          function: {
                            name: "state_patch",
                            arguments: <<~JSON_ARGS,
                              ```json
                              {
                                "request_id": "r1",
                                "ops": [{ "op": "set", "path": "/draft/foo", "value": "bar" }]
                              }
                              ```
                            JSON_ARGS
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context = TavernKit::PromptBuilder::Context.build({ tool_calling: { tool_call_transforms: [] } }, type: :app)

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)
    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    assert_equal "Done.", result[:assistant_text]
    assert_equal "bar", workspace.draft["foo"]
  end

  def test_default_preset_normalizes_blank_tool_call_arguments_before_execution
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_blank",
                          type: "function",
                          function: { name: "state_get", arguments: "" },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    tool_calling = TavernKit::VibeTavern::ToolCalling::Presets.default_tool_calling
    context = TavernKit::PromptBuilder::Context.build({ tool_calling: tool_calling }, type: :app)

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)
    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg

    parsed = JSON.parse(tool_msg.fetch("content"))
    assert_equal true, parsed["ok"]
  end

  def test_tool_call_transform_can_fix_blank_tool_call_arguments_before_execution
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_blank",
                          type: "function",
                          function: { name: "state_get", arguments: "" },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            tool_call_transforms: ["assistant_tool_calls_arguments_blank_to_empty_object"],
          },
        },
        type: :app,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)
    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg

    parsed = JSON.parse(tool_msg["content"])
    assert_equal true, parsed["ok"]
  end

  def test_tool_result_transform_can_modify_envelope_before_serialization
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_1",
                          type: "function",
                          function: { name: "state_get", arguments: JSON.generate({ workspace_id: workspace_id }) },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            tool_result_transforms: ["tool_result_compact_envelope"],
          },
        },
        type: :app,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)
    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg

    parsed = JSON.parse(tool_msg["content"])
    assert_equal true, parsed["ok"]
    refute parsed.key?("warnings")
    refute parsed.key?("errors")
  end

  def test_unknown_message_transform_raises_in_strict_mode
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: "Done." }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            message_transforms: ["unknown_transform"],
          },
        },
        type: :app,
      )

    tool_calls = [
      {
        "id" => "call_1",
        "type" => "function",
        "function" => { "name" => "state_get", "arguments" => "{}" },
      },
    ]

    history = [
      TavernKit::PromptBuilder::Message.new(role: :assistant, content: "", metadata: { tool_calls: tool_calls }),
    ]

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context, strict: true)

    assert_raises(ArgumentError) do
      runner.run(user_text: "hello", history: history)
    end
  end

  def test_unknown_tool_transform_raises_in_strict_mode
    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            tool_transforms: ["unknown_tool_transform"],
          },
        },
        type: :app,
      )

    workspace = ToolCallEvalTestWorkspace.new
    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:call) do |_env|
          raise "unexpected request"
        end
      end.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context, strict: true)

    assert_raises(ArgumentError) do
      runner.run(user_text: "hello")
    end
  end

  def test_unknown_response_transform_raises_in_strict_mode
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: "Done." }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            response_transforms: ["unknown_response_transform"],
          },
        },
        type: :app,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context, strict: true)

    assert_raises(ArgumentError) do
      runner.run(user_text: "hello")
    end
  end

  def test_unknown_tool_call_transform_raises_in_strict_mode
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        { id: "call_1", type: "function", function: { name: "state_get", arguments: "{}" } },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              },
            ),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            tool_call_transforms: ["unknown_tool_call_transform"],
          },
        },
        type: :app,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context, strict: true)

    assert_raises(ArgumentError) do
      runner.run(user_text: "hello")
    end

    assert_equal 1, requests.length
  end

  def test_unknown_tool_result_transform_raises_in_strict_mode
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        { id: "call_1", type: "function", function: { name: "state_get", arguments: "{}" } },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              },
            ),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            tool_result_transforms: ["unknown_tool_result_transform"],
          },
        },
        type: :app,
      )

    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context, strict: true)

    assert_raises(ArgumentError) do
      runner.run(user_text: "hello")
    end

    assert_equal 1, requests.length
  end

  def test_tool_use_can_be_disabled_to_avoid_sending_tools
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: { role: "assistant", content: "Done." },
                    finish_reason: "stop",
                  },
                ],
              }
            else
              raise "unexpected extra call"
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace, tool_use_mode: :disabled)

    result = runner.run(user_text: "hello")
    assert_equal "Done.", result[:assistant_text]

    req1 = JSON.parse(requests[0][:body])
    assert_nil req1["tools"]
    assert_nil req1["tool_choice"]
  end

  def test_tool_use_can_be_disabled_via_context
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: { role: "assistant", content: "Done." },
                    finish_reason: "stop",
                  },
                ],
              }
            else
              raise "unexpected extra call"
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    context = TavernKit::PromptBuilder::Context.build({ tool_calling: { tool_use_mode: :disabled } }, type: :app)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context)

    result = runner.run(user_text: "hello")
    assert_equal "Done.", result[:assistant_text]

    req1 = JSON.parse(requests[0][:body])
    assert_nil req1["tools"]
    assert_nil req1["tool_choice"]
  end

  def test_tool_use_mode_enforced_requires_at_least_one_tool_call
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body:
              JSON.generate(
                {
                  choices: [
                    {
                      message: { role: "assistant", content: "Done." },
                      finish_reason: "stop",
                    },
                  ],
                }
              ),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    runner = build_runner(client: client, model: "test-model", workspace: workspace, tool_use_mode: :enforced, system: "SYSTEM")

    error = assert_raises(TavernKit::VibeTavern::ToolCalling::ToolLoopRunner::ToolUseError) do
      runner.run(user_text: "workspace_id=#{workspace.id}")
    end

    assert_equal "NO_TOOL_CALLS", error.code
    assert error.details.is_a?(Hash)
    assert error.details.fetch(:trace, nil).is_a?(Array)
    assert error.details.fetch(:history, nil).is_a?(Array)

    req1 = JSON.parse(requests[0][:body])
    assert req1["tools"].is_a?(Array), "expected tools to be sent in enforced mode"
    assert_equal "auto", req1["tool_choice"]
  end

  def test_tool_use_mode_enforced_with_fatal_policy_raises_when_a_tool_ends_failed
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_get",
                          type: "function",
                          function: { name: "state_get", arguments: JSON.generate({ workspace_id: workspace_id }) },
                        },
                        {
                          id: "call_patch",
                          type: "function",
                          function: {
                            name: "state_patch",
                            arguments: JSON.generate(
                              {
                                workspace_id: workspace_id,
                                request_id: "r1",
                                ops: [{ op: "set", path: "/draft/foo", value: "bar" }],
                              }
                            ),
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            max_tool_output_bytes: 1_000,
            tool_failure_policy: :fatal,
          },
        },
        type: :app,
      )

    workspace = ToolCallEvalTestWorkspace.new(draft: { "big" => ("x" * 5_000) })
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context, tool_use_mode: :enforced)

    error = assert_raises(TavernKit::VibeTavern::ToolCalling::ToolLoopRunner::ToolUseError) do
      runner.run(user_text: "workspace_id=#{workspace.id}")
    end

    assert_equal "TOOL_ERROR", error.code
    assert_includes error.message, "state_get"
    assert error.details.is_a?(Hash)
    assert error.details.fetch(:trace, nil).is_a?(Array)
    assert error.details.fetch(:history, nil).is_a?(Array)
  end

  def test_tool_use_mode_enforced_with_tolerated_policy_allows_failed_tool_if_any_tool_succeeds
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          body = JSON.parse(env[:body])
          user_content = Array(body["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "user" }&.fetch("content", nil).to_s
          workspace_id = user_content[%r{\Aworkspace_id=(.+)\z}, 1].to_s

          response_body =
            if @call_count == 1
              {
                choices: [
                  {
                    message: {
                      role: "assistant",
                      content: "",
                      tool_calls: [
                        {
                          id: "call_get",
                          type: "function",
                          function: { name: "state_get", arguments: JSON.generate({ workspace_id: workspace_id }) },
                        },
                        {
                          id: "call_patch",
                          type: "function",
                          function: {
                            name: "state_patch",
                            arguments: JSON.generate(
                              {
                                workspace_id: workspace_id,
                                request_id: "r1",
                                ops: [{ op: "set", path: "/draft/foo", value: "bar" }],
                              }
                            ),
                          },
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
              }
            else
              {
                choices: [
                  { message: { role: "assistant", content: "Done." }, finish_reason: "stop" },
                ],
              }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    context =
      TavernKit::PromptBuilder::Context.build(
        {
          tool_calling: {
            max_tool_output_bytes: 1_000,
            tool_failure_policy: :tolerated,
          },
        },
        type: :app,
      )

    workspace = ToolCallEvalTestWorkspace.new(draft: { "big" => ("x" * 5_000) })
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, model: "test-model", workspace: workspace, context: context, tool_use_mode: :enforced)

    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    assert_equal "Done.", result[:assistant_text]
    assert_equal "bar", workspace.draft["foo"]
  end

  def test_tool_use_mode_relaxed_sends_tools_but_allows_no_tool_calls
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body:
              JSON.generate(
                {
                  choices: [
                    {
                      message: { role: "assistant", content: "Done." },
                      finish_reason: "stop",
                    },
                  ],
                }
              ),
          }
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    runner = build_runner(client: client, model: "test-model", workspace: workspace, tool_use_mode: :relaxed, system: "SYSTEM")

    result = runner.run(user_text: "workspace_id=#{workspace.id}")
    assert_equal "Done.", result[:assistant_text]

    req1 = JSON.parse(requests[0][:body])
    assert req1["tools"].is_a?(Array), "expected tools to be sent in relaxed mode"
    assert_equal "auto", req1["tool_choice"]
  end

  def test_tool_use_mode_relaxed_falls_back_to_chat_only_when_provider_rejects_tool_calling
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          if @call_count == 1
            {
              status: 400,
              headers: { "content-type" => "application/json" },
              body: JSON.generate({ error: { message: "Provider returned error" } }),
            }
          else
            {
              status: 200,
              headers: { "content-type" => "application/json" },
              body:
                JSON.generate(
                  {
                    choices: [
                      {
                        message: { role: "assistant", content: "Done." },
                        finish_reason: "stop",
                      },
                    ],
                  }
                ),
            }
          end
        end
      end.new(requests)

    workspace = ToolCallEvalTestWorkspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    runner =
      build_runner(
        client: client,
        model: "test-model",
        workspace: workspace,
        tool_use_mode: :relaxed,
        tool_calling_fallback_retry_count: 1,
        system: "SYSTEM",
      )

    result = runner.run(user_text: "workspace_id=#{workspace.id}")
    assert_equal "Done.", result[:assistant_text]

    req1 = JSON.parse(requests[0][:body])
    assert req1["tools"].is_a?(Array), "expected tools to be sent on first attempt"
    assert_equal "auto", req1["tool_choice"]

    req2 = JSON.parse(requests[1][:body])
    assert_nil req2["tools"]
    assert_nil req2["tool_choice"]
  end
end
