# frozen_string_literal: true

require_relative "tool_calling/message_transforms"
require_relative "tool_calling/response_transforms"
require_relative "preflight"
require_relative "runner_config"

module TavernKit
  module VibeTavern
    class PromptRunner
      PromptRequest =
        Data.define(
          :plan,
          :runtime,
          :messages,
          :options,
          :request,
          :strict,
          :response_transforms,
          :output_tags_config,
        ) do
          def initialize(
            plan:,
            runtime:,
            messages:,
            options:,
            request:,
            strict:,
            response_transforms:,
            output_tags_config: nil
          )
            super(
              plan: plan,
              runtime: runtime,
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
        runtime = runner_config.runtime
        build_history =
          if system_text.empty?
            history
          else
            [TavernKit::PromptBuilder::Message.new(role: :system, content: system_text)] + history
          end

        llm_options = deep_merge_hashes(runner_config.llm_options_defaults, normalize_llm_options(llm_options))
        plan =
          TavernKit::PromptBuilder.build(pipeline: runner_config.pipeline) do
            history build_history
            runtime runtime if runtime
            variables_store variables_store if variables_store
            llm_options llm_options unless llm_options.empty?
            strict strict
            meta :default_model_hint, runner_config.model
          end

        messages = plan.to_messages(dialect: dialect)
        options = (plan.llm_options || {}).dup
        request = { model: runner_config.model, messages: messages }.merge(options)

        if request.key?(:response_format)
          # Structured outputs should remain deterministic.
          options[:parallel_tool_calls] = false
          request[:parallel_tool_calls] = false
        end

        tools_present = request.key?(:tools) || request.key?(:tool_choice)
        TavernKit::VibeTavern::Preflight.validate_request!(
          stream: request.fetch(:stream, false) == true,
          tools: tools_present,
          response_format: request.key?(:response_format),
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
          runtime: runtime,
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

        assert_symbol_keys!(h)

        # Streaming is an execution mode, not a request option in this layer.
        # Use PromptRunner#perform_stream for streaming chat-only runs.
        if h.key?(:stream) || h.key?(:stream_options)
          raise ArgumentError, "streaming is not supported via llm_options; use PromptRunner#perform_stream instead"
        end

        h.delete(:model)
        h.delete(:messages)
        h
      end

      def assert_symbol_keys!(hash)
        hash.each_key do |key|
          raise ArgumentError, "Hash keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
        end
      end

      def deep_merge_hashes(left, right)
        out = (left.is_a?(Hash) ? left : {}).dup
        (right.is_a?(Hash) ? right : {}).each do |key, value|
          if out[key].is_a?(Hash) && value.is_a?(Hash)
            out[key] = deep_merge_hashes(out[key], value)
          else
            out[key] = value
          end
        end
        out
      end
    end
  end
end
