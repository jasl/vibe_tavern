# frozen_string_literal: true

require_relative "test_helper"

class GenerationTest < Minitest::Test
  class FakeTokenEstimator
    def estimate(text, model_hint: nil)
      _ = model_hint
      text.to_s.length
    end
  end

  class FakeClient
    attr_reader :requests

    def initialize(body:)
      @requests = []
      @body = body
    end

    def chat_completions(**params)
      @requests << params
      SimpleInference::Response.new(status: 200, headers: {}, body: @body, raw_body: "{}")
    end
  end

  def build_runner_config(context: nil, capabilities_overrides: nil)
    TavernKit::VibeTavern::RunnerConfig.build(
      provider: "openrouter",
      model: "test-model",
      context: context,
      capabilities_overrides: capabilities_overrides,
    )
  end

  def test_chat_mode_returns_output_with_assistant_text_output_tags_applied_but_keeps_assistant_message_raw
    runner_config =
      build_runner_config(
        context: {
          output_tags: {
            enabled: true,
            rules: [
              { tag: "think", action: :drop },
            ],
          },
        },
      )

    client =
      FakeClient.new(
        body: {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => "<think>secret</think>ok",
              },
              "finish_reason" => "stop",
            },
          ],
          "usage" => { "prompt_tokens" => 1 },
        },
      )

    history = [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")]

    generation = TavernKit::VibeTavern::Generation.chat(client: client, runner_config: runner_config, history: history)
    preview = generation.prompt_request
    assert_kind_of TavernKit::VibeTavern::PromptRunner::PromptRequest, preview

    result = generation.run
    assert result.success?

    output = result.value
    assert_equal :chat, output.mode
    assert_equal "ok", output.assistant_text
    assert_equal "<think>secret</think>ok", output.assistant_message.fetch("content")
    assert_kind_of TavernKit::VibeTavern::PromptRunner::PromptResult, output.prompt_result
  end

  def test_chat_mode_returns_prompt_too_long_when_prompt_exceeds_context_window_tokens
    runner_config =
      build_runner_config(
        context: {
          token_estimation: { token_estimator: FakeTokenEstimator.new, model_hint: "test" },
        },
        capabilities_overrides: { context_window_tokens: 1, reserved_response_tokens: 0 },
      )

    client =
      FakeClient.new(
        body: {
          "choices" => [
            {
              "message" => { "role" => "assistant", "content" => "ok" },
              "finish_reason" => "stop",
            },
          ],
        },
      )

    history = [TavernKit::PromptBuilder::Message.new(role: :user, content: "aa")]
    generation = TavernKit::VibeTavern::Generation.chat(client: client, runner_config: runner_config, history: history)

    result = generation.run
    assert result.failure?
    assert_equal "PROMPT_TOO_LONG", result.code
    assert_equal 2, result.value.fetch(:estimated_tokens)
    assert_equal 1, result.value.fetch(:max_tokens)
    assert_equal 0, result.value.fetch(:reserve_tokens)
    assert_equal 1, result.value.fetch(:limit_tokens)
  end

  def test_chat_mode_returns_invalid_input_when_history_and_system_are_empty
    runner_config = build_runner_config
    client =
      FakeClient.new(
        body: {
          "choices" => [
            {
              "message" => { "role" => "assistant", "content" => "ok" },
              "finish_reason" => "stop",
            },
          ],
        },
      )

    generation = TavernKit::VibeTavern::Generation.chat(client: client, runner_config: runner_config, history: [])
    result = generation.run

    assert result.failure?
    assert_equal "INVALID_INPUT", result.code
    assert_equal ["prompt is empty"], result.errors
  end

  def test_tool_loop_mode_can_run_with_tool_use_mode_disabled_and_returns_tool_loop_result
    runner_config =
      build_runner_config(
        context: {
          tool_calling: {
            tool_use_mode: :disabled,
          },
        },
      )

    client =
      FakeClient.new(
        body: {
          "choices" => [
            {
              "message" => { "role" => "assistant", "content" => "ok" },
              "finish_reason" => "stop",
            },
          ],
        },
      )

    generation =
      TavernKit::VibeTavern::Generation.tool_loop(
        client: client,
        runner_config: runner_config,
        tool_executor: nil,
        user_text: "hi",
      )

    result = generation.run
    assert result.success?

    output = result.value
    assert_equal :tool_loop, output.mode
    assert_equal "ok", output.assistant_text
    assert_kind_of Hash, output.tool_loop_result
    assert_equal "ok", output.tool_loop_result.fetch(:assistant_text)
  end

  def test_tool_loop_mode_returns_failure_when_tool_use_is_enforced_and_no_tool_calls_are_made
    runner_config =
      build_runner_config(
        context: {
          tool_calling: { tool_use_mode: :enforced },
        },
      )

    client =
      FakeClient.new(
        body: {
          "choices" => [
            {
              "message" => { "role" => "assistant", "content" => "ok" },
              "finish_reason" => "stop",
            },
          ],
        },
      )

    generation =
      TavernKit::VibeTavern::Generation.tool_loop(
        client: client,
        runner_config: runner_config,
        tool_executor: Object.new,
        user_text: "hi",
      )

    result = generation.run
    assert result.failure?
    assert_equal "NO_TOOL_CALLS", result.code
  end

  def test_directives_mode_returns_directives_result_when_envelope_parses
    runner_config = build_runner_config

    client =
      FakeClient.new(
        body: {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => "{\"assistant_text\":\"OK\",\"directives\":[{\"type\":\"test\",\"payload\":{}}]}",
              },
              "finish_reason" => "stop",
            },
          ],
        },
      )

    history = [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")]

    generation = TavernKit::VibeTavern::Generation.directives(client: client, runner_config: runner_config, history: history)
    result = generation.run
    assert result.success?

    output = result.value
    assert_equal :directives, output.mode
    assert_equal "OK", output.assistant_text
    assert_kind_of Hash, output.directives_result
    assert_equal true, output.directives_result.fetch(:ok)
  end
end
