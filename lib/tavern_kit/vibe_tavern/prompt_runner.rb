# frozen_string_literal: true

require_relative "tool_calling/message_transforms"
require_relative "tool_calling/response_transforms"
require_relative "preflight"
require_relative "request_policy"
require_relative "runner_config"

module TavernKit
  module VibeTavern
    class PromptRunner
      PromptRequest =
        Data.define(
          :plan,
          :context,
          :capabilities,
          :messages,
          :options,
          :request,
          :strict,
          :response_transforms,
          :output_tags_config,
        ) do
          def initialize(
            plan:,
            context:,
            capabilities:,
            messages:,
            options:,
            request:,
            strict:,
            response_transforms:,
            output_tags_config: nil
          )
            super(
              plan: plan,
              context: context,
              capabilities: capabilities,
              messages: messages,
              options: options,
              request: request,
              strict: strict == true,
              response_transforms: Array(response_transforms),
              output_tags_config: output_tags_config,
            )
          end
        end

      PromptResult =
        Data.define(
          :prompt_request,
          :response,
          :body,
          :assistant_message,
          :finish_reason,
          :elapsed_ms,
        )

      def initialize(client:)
        @client = client
      end

      def build_request(
        runner_config:,
        history:,
        system: nil,
        variables_store: nil,
        strict: false,
        llm_options: nil,
        dialect: :openai,
        message_transforms: nil,
        response_transforms: nil
      )
        raise ArgumentError, "runner_config is required" unless runner_config.is_a?(TavernKit::VibeTavern::RunnerConfig)
        raise ArgumentError, "model is required" if runner_config.model.to_s.strip.empty?

        strict = strict == true
        history = Array(history)

        system_text = system.to_s
        context = runner_config.context
        build_history =
          if system_text.empty?
            history
          else
            [TavernKit::PromptBuilder::Message.new(role: :system, content: system_text)] + history
          end

        llm_options = TavernKit::Utils.deep_merge_hashes(runner_config.llm_options_defaults, normalize_llm_options(llm_options))
        plan =
          TavernKit::PromptBuilder.build(pipeline: runner_config.pipeline, context: context) do
            history build_history
            variables_store variables_store if variables_store
            llm_options llm_options unless llm_options.empty?
            strict strict
            meta :default_model_hint, runner_config.model
          end

        messages = plan.to_messages(dialect: dialect)
        options = (plan.llm_options || {}).dup
        TavernKit::VibeTavern::RequestPolicy.normalize_options!(options, capabilities: runner_config.capabilities)
        request = { model: runner_config.model, messages: messages }.merge(options)
        TavernKit::VibeTavern::RequestPolicy.filter_request!(request, capabilities: runner_config.capabilities)

        tools_present = request.key?(:tools) || request.key?(:tool_choice)
        TavernKit::VibeTavern::Preflight.validate_request!(
          capabilities: runner_config.capabilities,
          stream: request.fetch(:stream, false) == true,
          tools: tools_present,
          response_format: request.fetch(:response_format, nil),
        )

        message_transforms = Array(message_transforms).map(&:to_s).map(&:strip).reject(&:empty?)
        if message_transforms.any?
          TavernKit::VibeTavern::ToolCalling::MessageTransforms.apply!(
            request.fetch(:messages),
            message_transforms,
            strict: strict,
          )
        end

        response_transforms = Array(response_transforms).map(&:to_s).map(&:strip).reject(&:empty?)

        PromptRequest.new(
          plan: plan,
          context: context,
          capabilities: runner_config.capabilities,
          messages: messages,
          options: options,
          request: request,
          strict: strict,
          response_transforms: response_transforms,
          output_tags_config: runner_config.output_tags,
        )
      end

      def perform(prompt_request)
        prompt_request = prompt_request.is_a?(PromptRequest) ? prompt_request : nil
        raise ArgumentError, "prompt_request is required" unless prompt_request

        if prompt_request.request[:stream] == true
          raise ArgumentError, "PromptRunner does not support streaming via #perform; use #perform_stream instead"
        end

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = @client.chat_completions(**prompt_request.request)
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

        body = response.body.is_a?(Hash) ? response.body : {}

        assistant_message = body.dig("choices", 0, "message")
        assistant_message = {} unless assistant_message.is_a?(Hash)

        response_transforms = prompt_request.response_transforms
        if response_transforms.any?
          TavernKit::VibeTavern::ToolCalling::ResponseTransforms.apply!(
            assistant_message,
            response_transforms,
            strict: prompt_request.strict,
            output_tags_config: prompt_request.output_tags_config,
          )
        end

        PromptResult.new(
          prompt_request: prompt_request,
          response: response,
          body: body,
          assistant_message: assistant_message,
          finish_reason: body.dig("choices", 0, "finish_reason"),
          elapsed_ms: elapsed_ms,
        )
      end

      def perform_stream(prompt_request, include_usage: true, &on_delta)
        prompt_request = prompt_request.is_a?(PromptRequest) ? prompt_request : nil
        raise ArgumentError, "prompt_request is required" unless prompt_request

        req = prompt_request.request
        if req.key?(:tools) || req.key?(:tool_choice)
          raise ArgumentError, "PromptRunner#perform_stream does not support tool calling; use ToolLoopRunner (non-streaming)"
        end

        if req.key?(:response_format)
          raise ArgumentError, "PromptRunner#perform_stream does not support response_format; use #perform instead"
        end

        capabilities = prompt_request.capabilities
        if capabilities && !capabilities.supports_streaming
          raise ArgumentError, "provider/model does not support streaming"
        end

        unless @client.respond_to?(:chat)
          raise ArgumentError, "client does not support streaming chat (missing #chat)"
        end

        request = req.dup
        model = request.delete(:model)
        messages = request.delete(:messages)

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        chat_result =
          @client.chat(
            model: model,
            messages: messages,
            stream: true,
            include_usage: include_usage == true,
            **request,
            &on_delta
          )
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

        usage = chat_result.respond_to?(:usage) ? chat_result.usage : nil
        usage_json =
          if usage.is_a?(Hash)
            usage.each_with_object({}) { |(k, v), out| out[k.to_s] = v }
          end
        body = usage_json ? { "usage" => usage_json } : {}

        assistant_message = {
          "role" => "assistant",
          "content" => chat_result.respond_to?(:content) ? chat_result.content.to_s : "",
        }

        response_transforms = prompt_request.response_transforms
        if response_transforms.any?
          TavernKit::VibeTavern::ToolCalling::ResponseTransforms.apply!(
            assistant_message,
            response_transforms,
            strict: prompt_request.strict,
            output_tags_config: prompt_request.output_tags_config,
          )
        end

        PromptResult.new(
          prompt_request: prompt_request,
          response: chat_result.respond_to?(:response) ? chat_result.response : nil,
          body: body,
          assistant_message: assistant_message,
          finish_reason: chat_result.respond_to?(:finish_reason) ? chat_result.finish_reason : nil,
          elapsed_ms: elapsed_ms,
        )
      end

      private

      def normalize_llm_options(value)
        h = value.nil? ? {} : value
        raise ArgumentError, "llm_options must be a Hash" unless h.is_a?(Hash)

        TavernKit::Utils.assert_symbol_keys!(h, path: "llm_options")

        # Streaming is an execution mode, not a request option in this layer.
        # Use PromptRunner#perform_stream for streaming chat-only runs.
        if h.key?(:stream) || h.key?(:stream_options)
          raise ArgumentError, "streaming is not supported via llm_options; use PromptRunner#perform_stream instead"
        end

        h.delete(:model)
        h.delete(:messages)
        h
      end
    end
  end
end
