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
                            name: "state.get",
                            arguments: JSON.generate({ workspace_id: workspace_id }),
                          },
                        },
                        {
                          id: "call_2",
                          type: "function",
                          function: {
                            name: "state.patch",
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
    assert_includes tool_names, "state.get"
    assert_includes tool_names, "state.patch"
    refute_includes tool_names, "facts.commit"

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
                            name: "facts.commit",
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
end
