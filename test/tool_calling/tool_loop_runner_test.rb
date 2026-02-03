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

  def test_missing_workspace_id_returns_workspace_not_found
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
end
