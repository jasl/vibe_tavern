# frozen_string_literal: true

require_relative "directives/runner"
require_relative "output_tags"
require_relative "prompt_runner"
require_relative "result"
require_relative "runner_config"
require_relative "tool_calling/tool_loop_runner"

module TavernKit
  module VibeTavern
    class Generation
      MODES = %i[chat tool_loop directives].freeze

      Output =
        Data.define(
          :mode,
          :assistant_text,
          :assistant_message,
          :usage,
          :finish_reason,
          :elapsed_ms,
          :prompt_request,
          :prompt_result,
          :tool_loop_result,
          :directives_result,
        )

      def self.chat(client:, runner_config:, history:, **kwargs)
        prompt_runner = TavernKit::VibeTavern::PromptRunner.new(client: client)
        new(mode: :chat, prompt_runner: prompt_runner, runner_config: runner_config, history: history, **kwargs)
      end

      def self.tool_loop(client:, runner_config:, tool_executor:, user_text:, history: nil, **kwargs)
        prompt_runner = TavernKit::VibeTavern::PromptRunner.new(client: client)
        new(
          mode: :tool_loop,
          prompt_runner: prompt_runner,
          runner_config: runner_config,
          history: history,
          tool_executor: tool_executor,
          user_text: user_text,
          **kwargs,
        )
      end

      def self.directives(client:, runner_config:, history:, **kwargs)
        prompt_runner = TavernKit::VibeTavern::PromptRunner.new(client: client)
        new(mode: :directives, prompt_runner: prompt_runner, runner_config: runner_config, history: history, **kwargs)
      end

      def initialize(
        mode:,
        prompt_runner:,
        runner_config:,
        history:,
        system: nil,
        variables_store: nil,
        strict: false,
        llm_options: nil,
        dialect: :openai,
        message_transforms: nil,
        response_transforms: nil,
        tool_executor: nil,
        registry: nil,
        user_text: nil,
        max_turns: nil,
        final_stream: false,
        on_event: nil,
        structured_output_options: nil,
        result_validator: nil
      )
        mode = mode.to_s.strip.downcase.tr("-", "_").to_sym
        raise ArgumentError, "mode is required" if mode.nil? || mode == :""
        raise ArgumentError, "mode not supported: #{mode.inspect}" unless MODES.include?(mode)
        raise ArgumentError, "prompt_runner is required" unless prompt_runner.is_a?(TavernKit::VibeTavern::PromptRunner)
        raise ArgumentError, "runner_config is required" unless runner_config.is_a?(TavernKit::VibeTavern::RunnerConfig)

        @mode = mode
        @prompt_runner = prompt_runner
        @runner_config = runner_config
        @history = Array(history)
        @system = system.to_s
        @variables_store = variables_store
        @strict = strict == true
        @llm_options = llm_options
        @dialect = dialect
        @message_transforms = message_transforms
        @response_transforms = response_transforms

        @tool_executor = tool_executor
        @registry = registry
        @user_text = user_text.to_s
        @max_turns = max_turns
        @final_stream = final_stream == true
        @on_event = on_event

        @structured_output_options = structured_output_options
        @result_validator = result_validator
      end

      def prompt_request
        raise ArgumentError, "prompt_request is only supported for mode=:chat" unless mode == :chat

        req =
          @prompt_runner.build_request(
            runner_config: @runner_config,
            history: @history,
            system: @system,
            variables_store: @variables_store,
            strict: @strict,
            llm_options: @llm_options,
            dialect: @dialect,
            message_transforms: @message_transforms,
            response_transforms: @response_transforms,
          )

        messages = req.messages
        raise ArgumentError, "prompt is empty" unless messages.is_a?(Array) && messages.any?

        req
      end

      def run
        case mode
        when :chat
          run_chat
        when :tool_loop
          run_tool_loop
        when :directives
          run_directives
        else
          raise ArgumentError, "Unknown mode: #{mode.inspect}"
        end
      end

      private

      attr_reader :mode

      def run_chat
        prompt_request = self.prompt_request
        prompt_result = @prompt_runner.perform(prompt_request)

        assistant_message = prompt_result.assistant_message
        assistant_message = {} unless assistant_message.is_a?(Hash)

        assistant_content = assistant_message.fetch("content", "").to_s
        assistant_text =
          TavernKit::VibeTavern::OutputTags.transform(
            assistant_content,
            config: @runner_config.output_tags,
          )

        usage = prompt_result.body.fetch("usage", nil)
        usage = nil unless usage.is_a?(Hash)

        output =
          Output.new(
            mode: :chat,
            assistant_text: assistant_text,
            assistant_message: assistant_message,
            usage: usage,
            finish_reason: prompt_result.finish_reason,
            elapsed_ms: prompt_result.elapsed_ms,
            prompt_request: prompt_request,
            prompt_result: prompt_result,
            tool_loop_result: nil,
            directives_result: nil,
          )

        TavernKit::VibeTavern::Result.success(value: output)
      rescue TavernKit::MaxTokensExceededError => e
        TavernKit::VibeTavern::Result.failure(
          errors: [e.message],
          code: "PROMPT_TOO_LONG",
          value: {
            estimated_tokens: e.estimated_tokens,
            max_tokens: e.max_tokens,
            reserve_tokens: e.reserve_tokens,
            limit_tokens: e.limit_tokens,
          },
        )
      rescue SimpleInference::Errors::Error => e
        TavernKit::VibeTavern::Result.failure(
          errors: [e.message],
          code: "LLM_REQUEST_FAILED",
          value: {
            status: e.respond_to?(:status) ? e.status : nil,
            error_class: e.class.name,
          },
        )
      rescue TavernKit::PipelineError, TavernKit::StrictModeError, ArgumentError => e
        TavernKit::VibeTavern::Result.failure(
          errors: [e.message],
          code: "INVALID_INPUT",
          value: { error_class: e.class.name },
        )
      end

      def run_tool_loop
        if @user_text.strip.empty? && @history.empty? && @system.strip.empty?
          raise ArgumentError, "prompt is empty"
        end

        tool_loop_runner =
          TavernKit::VibeTavern::ToolCalling::ToolLoopRunner.new(
            prompt_runner: @prompt_runner,
            runner_config: @runner_config,
            tool_executor: @tool_executor,
            variables_store: @variables_store,
            registry: @registry,
            system: @system,
            strict: @strict,
          )

        raw_result =
          tool_loop_runner.run(
            user_text: @user_text,
            history: @history,
            max_turns: @max_turns || TavernKit::VibeTavern::ToolCalling::ToolLoopRunner::DEFAULT_MAX_TURNS,
            on_event: @on_event,
            final_stream: @final_stream,
          )

        assistant_text = raw_result.fetch(:assistant_text, "").to_s
        assistant_message = { "role" => "assistant", "content" => assistant_text }

        output =
          Output.new(
            mode: :tool_loop,
            assistant_text: assistant_text,
            assistant_message: assistant_message,
            usage: nil,
            finish_reason: nil,
            elapsed_ms: nil,
            prompt_request: nil,
            prompt_result: nil,
            tool_loop_result: raw_result,
            directives_result: nil,
          )

        TavernKit::VibeTavern::Result.success(value: output)
      rescue TavernKit::MaxTokensExceededError => e
        TavernKit::VibeTavern::Result.failure(
          errors: [e.message],
          code: "PROMPT_TOO_LONG",
          value: {
            estimated_tokens: e.estimated_tokens,
            max_tokens: e.max_tokens,
            reserve_tokens: e.reserve_tokens,
            limit_tokens: e.limit_tokens,
          },
        )
      rescue TavernKit::VibeTavern::ToolCalling::ToolLoopRunner::ToolUseError => e
        TavernKit::VibeTavern::Result.failure(
          errors: [e.message],
          code: e.code,
          value: e.details,
        )
      rescue SimpleInference::Errors::Error => e
        TavernKit::VibeTavern::Result.failure(
          errors: [e.message],
          code: "LLM_REQUEST_FAILED",
          value: {
            status: e.respond_to?(:status) ? e.status : nil,
            error_class: e.class.name,
          },
        )
      rescue TavernKit::PipelineError, TavernKit::StrictModeError, ArgumentError => e
        TavernKit::VibeTavern::Result.failure(
          errors: [e.message],
          code: "INVALID_INPUT",
          value: { error_class: e.class.name },
        )
      end

      def run_directives
        directives_runner =
          TavernKit::VibeTavern::Directives::Runner.new(
            prompt_runner: @prompt_runner,
            runner_config: @runner_config,
          )

        raw_result =
          directives_runner.run(
            history: @history,
            system: @system,
            variables_store: @variables_store,
            strict: @strict,
            llm_options: @llm_options,
            dialect: @dialect,
            structured_output_options: @structured_output_options,
            result_validator: @result_validator,
          )

        if raw_result.is_a?(Hash) && raw_result.fetch(:ok, false) == true
          assistant_text = raw_result.fetch(:assistant_text, "").to_s
          assistant_message = { "role" => "assistant", "content" => assistant_text }

          output =
            Output.new(
              mode: :directives,
              assistant_text: assistant_text,
              assistant_message: assistant_message,
              usage: nil,
              finish_reason: raw_result.fetch(:finish_reason, nil),
              elapsed_ms: raw_result.fetch(:elapsed_ms, nil),
              prompt_request: nil,
              prompt_result: nil,
              tool_loop_result: nil,
              directives_result: raw_result,
            )

          return TavernKit::VibeTavern::Result.success(value: output)
        end

        TavernKit::VibeTavern::Result.failure(
          errors: ["directives generation failed"],
          code: "DIRECTIVES_FAILED",
          value: raw_result,
        )
      rescue TavernKit::MaxTokensExceededError => e
        TavernKit::VibeTavern::Result.failure(
          errors: [e.message],
          code: "PROMPT_TOO_LONG",
          value: {
            estimated_tokens: e.estimated_tokens,
            max_tokens: e.max_tokens,
            reserve_tokens: e.reserve_tokens,
            limit_tokens: e.limit_tokens,
          },
        )
      rescue SimpleInference::Errors::Error => e
        TavernKit::VibeTavern::Result.failure(
          errors: [e.message],
          code: "LLM_REQUEST_FAILED",
          value: {
            status: e.respond_to?(:status) ? e.status : nil,
            error_class: e.class.name,
          },
        )
      rescue TavernKit::PipelineError, TavernKit::StrictModeError, ArgumentError => e
        TavernKit::VibeTavern::Result.failure(
          errors: [e.message],
          code: "INVALID_INPUT",
          value: { error_class: e.class.name },
        )
      end
    end
  end
end
