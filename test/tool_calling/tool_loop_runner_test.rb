# frozen_string_literal: true

require_relative "test_helper"

class ToolLoopRunnerTest < Minitest::Test
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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new

    client =
      SimpleInference::Client.new(
        base_url: "http://example.com",
        api_key: "secret",
        adapter: adapter,
      )

    runner =
      TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(
        client: client,
        model: "test-model",
        workspace: workspace,
      )

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

    assistant_with_calls = msgs2.find { |m| m["role"] == "assistant" && m.key?("tool_calls") }
    refute_nil assistant_with_calls

    tool_result = msgs2.find { |m| m["role"] == "tool" && m.key?("tool_call_id") }
    refute_nil tool_result
  end

  def test_fix_empty_final_retries_without_tools
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
            when 2
              # Simulate providers that emit an empty final message after tool calls.
              {
                choices: [
                  {
                    message: { role: "assistant", content: "" },
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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    runner = TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(client: client, model: "test-model", workspace: workspace)

    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    assert_equal "Done.", result[:assistant_text]
    assert_equal 3, requests.length

    req3 = JSON.parse(requests[2][:body])
    refute req3.key?("tools")
    refute req3.key?("tool_choice")
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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    runner = TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(client: client, model: "test-model", workspace: workspace)

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_result = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    runner =
      TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(
        client: client,
        model: "test-model",
        workspace: workspace,
        system: "SYSTEM INSTRUCTIONS",
      )

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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(client: client, model: "test-model", workspace: workspace)

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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(client: client, model: "test-model", workspace: workspace)

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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(client: client, model: "test-model", workspace: workspace)

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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(client: client, model: "test-model", workspace: workspace)

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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(client: client, model: "test-model", workspace: workspace)

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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(client: client, model: "test-model", workspace: workspace)

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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(client: client, model: "test-model", workspace: workspace)

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
    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new(draft: { "big" => ("x" * (max + 10_000)) })

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(client: client, model: "test-model", workspace: workspace)

    runner.run(user_text: "workspace_id=#{workspace.id}")

    req2 = JSON.parse(requests[1][:body])
    tool_msg = Array(req2["messages"]).find { |m| m.is_a?(Hash) && m["role"] == "tool" }
    refute_nil tool_msg

    parsed = JSON.parse(tool_msg["content"])
    assert_equal false, parsed["ok"]
    assert_includes parsed.dig("errors", 0, "code"), "TOOL_OUTPUT_TOO_LARGE"
    refute_includes tool_msg["content"], "x" * 1000
  end

  def test_fix_empty_final_retries_without_tools
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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner =
      TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(
        client: client,
        model: "test-model",
        workspace: workspace,
        system: "SYSTEM",
        fix_empty_final: true,
      )

    result = runner.run(user_text: "workspace_id=#{workspace.id}")

    assert_equal "Done.", result[:assistant_text]
    assert_equal "bar", workspace.draft["foo"]

    assert_equal 3, requests.length

    req3 = JSON.parse(requests[2][:body])
    assert_nil req3["tool_choice"]
    assert_nil req3["tools"]
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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner =
      TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(
        client: client,
        model: "test-model",
        workspace: workspace,
        tool_use_mode: :disabled,
      )

    result = runner.run(user_text: "hello")
    assert_equal "Done.", result[:assistant_text]

    req1 = JSON.parse(requests[0][:body])
    assert_nil req1["tools"]
    assert_nil req1["tool_choice"]
  end

  def test_tool_use_can_be_disabled_via_runtime
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

    runtime = TavernKit::Runtime::Base.build({ tool_calling: { tool_use_mode: :disabled } }, type: :app)

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner =
      TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(
        client: client,
        model: "test-model",
        workspace: workspace,
        runtime: runtime,
      )

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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    runner =
      TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(
        client: client,
        model: "test-model",
        workspace: workspace,
        tool_use_mode: :enforced,
        system: "SYSTEM",
      )

    error = assert_raises(TavernKit::VibeTavern::ToolCalling::ToolLoopRunner::ToolUseError) do
      runner.run(user_text: "workspace_id=#{workspace.id}")
    end

    assert_equal "NO_TOOL_CALLS", error.code

    req1 = JSON.parse(requests[0][:body])
    assert req1["tools"].is_a?(Array), "expected tools to be sent in enforced mode"
    assert_equal "auto", req1["tool_choice"]
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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    runner =
      TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(
        client: client,
        model: "test-model",
        workspace: workspace,
        tool_use_mode: :relaxed,
        system: "SYSTEM",
      )

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

    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    runner =
      TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(
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
