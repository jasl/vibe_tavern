# frozen_string_literal: true

require_relative "tool_calling/message_transforms"
require_relative "tool_calling/response_transforms"

module TavernKit
  module VibeTavern
    class PromptRunner
      PromptRequest =
        Data.define(:plan, :messages, :options, :request, :strict, :response_transforms) do
          def initialize(plan:, messages:, options:, request:, strict:, response_transforms:)
            super(
              plan: plan,
              messages: messages,
              options: options,
              request: request,
              strict: strict == true,
              response_transforms: Array(response_transforms),
            )
          end
        end

      PromptResult =
        Data.define(:prompt_request, :response, :body, :assistant_message, :finish_reason, :elapsed_ms) do
          def initialize(prompt_request:, response:, body:, assistant_message:, finish_reason:, elapsed_ms:)
            super(
              prompt_request: prompt_request,
              response: response,
              body: body,
              assistant_message: assistant_message,
              finish_reason: finish_reason,
              elapsed_ms: elapsed_ms,
            )
          end
        end

      def initialize(client:, model:)
        @client = client
        @model = model.to_s
      end

      def build_request(
        history:,
        system: nil,
        runtime: nil,
        variables_store: nil,
        strict: false,
        llm_options: nil,
        dialect: :openai,
        message_transforms: nil,
        response_transforms: nil
      )
        raise ArgumentError, "model is required" if @model.strip.empty?

        strict = strict == true
        history = Array(history)

        system_text = system.to_s
        build_history =
          if system_text.empty?
            history
          else
            [TavernKit::Prompt::Message.new(role: :system, content: system_text)] + history
          end

        llm_options = llm_options.is_a?(Hash) ? llm_options : {}
        plan =
          TavernKit::VibeTavern.build do
            history build_history
            runtime runtime if runtime
            variables_store variables_store if variables_store
            llm_options llm_options unless llm_options.empty?
            strict strict
          end

        messages = plan.to_messages(dialect: dialect)
        options = plan.llm_options || {}
        request = { model: @model, messages: messages }.merge(options)

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
          messages: messages,
          options: options,
          request: request,
          strict: strict,
          response_transforms: response_transforms,
        )
      end

      def perform(prompt_request)
        prompt_request = prompt_request.is_a?(PromptRequest) ? prompt_request : nil
        raise ArgumentError, "prompt_request is required" unless prompt_request

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
    end
  end
end
