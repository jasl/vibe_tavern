# frozen_string_literal: true

require_relative "tool_calling/message_transforms"
require_relative "tool_calling/response_transforms"
require_relative "directives"
require_relative "output_tags"

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
          :structured_output_kind,
          :structured_output_options,
        ) do
          def initialize(
            plan:,
            runtime:,
            messages:,
            options:,
            request:,
            strict:,
            response_transforms:,
            structured_output_kind: nil,
            structured_output_options: nil
          )
            super(
              plan: plan,
              runtime: runtime,
              messages: messages,
              options: options,
              request: request,
              strict: strict == true,
              response_transforms: Array(response_transforms),
              structured_output_kind: structured_output_kind&.to_sym,
              structured_output_options: structured_output_options.is_a?(Hash) ? structured_output_options : {},
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
          :structured_output,
          :structured_output_error,
          :structured_output_warnings,
        ) do
          def initialize(
            prompt_request:,
            response:,
            body:,
            assistant_message:,
            finish_reason:,
            elapsed_ms:,
            structured_output: nil,
            structured_output_error: nil,
            structured_output_warnings: nil
          )
            super(
              prompt_request: prompt_request,
              response: response,
              body: body,
              assistant_message: assistant_message,
              finish_reason: finish_reason,
              elapsed_ms: elapsed_ms,
              structured_output: structured_output,
              structured_output_error: structured_output_error,
              structured_output_warnings: Array(structured_output_warnings),
            )
          end
        end

      def initialize(client:, model:, llm_options_defaults: nil)
        @client = client
        @model = model.to_s
        @llm_options_defaults = normalize_llm_options_defaults(llm_options_defaults)
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
        response_transforms: nil,
        structured_output: nil,
        structured_output_options: nil
      )
        raise ArgumentError, "model is required" if @model.strip.empty?

        strict = strict == true
        history = Array(history)

        system_text = system.to_s
        runtime = normalize_runtime(runtime)
        build_history =
          if system_text.empty?
            history
          else
            [TavernKit::Prompt::Message.new(role: :system, content: system_text)] + history
          end

        llm_options = deep_merge_hashes(@llm_options_defaults, normalize_llm_options(llm_options))
        plan =
          TavernKit::Prompt::DSL.build(pipeline: Pipeline) do
            history build_history
            runtime runtime if runtime
            variables_store variables_store if variables_store
            llm_options llm_options unless llm_options.empty?
            strict strict
            meta :default_model_hint, @model
          end

        messages = plan.to_messages(dialect: dialect)
        options = (plan.llm_options || {}).dup
        request = { model: @model, messages: messages }.merge(options)

        structured_output_kind = structured_output&.to_sym
        structured_output_options =
          if structured_output_options.is_a?(Hash)
            TavernKit::Utils.deep_symbolize_keys(structured_output_options)
          else
            {}
          end

        if structured_output_kind == :directives_v1
          registry = structured_output_options[:registry]
          registry = nil unless registry.respond_to?(:types)

          schema_name =
            structured_output_options[:schema_name] || TavernKit::VibeTavern::Directives::Schema::NAME

          allowed_types =
            structured_output_options[:allowed_types] || (registry ? registry.types : nil)

          inject_response_format =
            structured_output_options.key?(:inject_response_format) ? structured_output_options[:inject_response_format] : true

          if inject_response_format != false
            options[:response_format] ||=
              TavernKit::VibeTavern::Directives::Schema.response_format(
                strict: true,
                name: schema_name,
                types: allowed_types,
              )
            request[:response_format] ||= options[:response_format]
          end
        end

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
          structured_output_kind: structured_output_kind,
          structured_output_options: structured_output_options,
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
            runtime: prompt_request.runtime,
          )
        end

        runtime = prompt_request.runtime
        output_tags_enabled = runtime && TavernKit::VibeTavern::OutputTags.enabled?(runtime)

        if output_tags_enabled && prompt_request.structured_output_kind.nil?
          assistant_message["content"] =
            TavernKit::VibeTavern::OutputTags.transform(
              assistant_message.fetch("content", nil),
              runtime: runtime,
            )
        end

        structured_output = nil
        structured_output_error = nil
        structured_output_warnings = nil

        if prompt_request.structured_output_kind == :directives_v1
          opts = prompt_request.structured_output_options
          registry = opts.is_a?(Hash) ? opts[:registry] : nil
          registry = nil unless registry.respond_to?(:types)

          allowed_types =
            opts.is_a?(Hash) ? opts[:allowed_types] : nil
          allowed_types = registry.types if allowed_types.nil? && registry

          type_aliases =
            opts.is_a?(Hash) ? opts[:type_aliases] : nil
          type_aliases = registry.type_aliases if type_aliases.nil? && registry&.respond_to?(:type_aliases)

          payload_validator =
            opts.is_a?(Hash) ? opts[:payload_validator] : nil

          tool_calls = assistant_message.fetch("tool_calls", nil)
          tool_calls_present =
            case tool_calls
            when Array
              tool_calls.any?
            when Hash
              tool_calls.any?
            else
              false
            end

          # If this turn contains tool calls, do not attempt to parse directives.
          unless tool_calls_present
            raw_max_bytes = opts.is_a?(Hash) ? opts[:max_bytes] : nil
            max_bytes =
              begin
                Integer(raw_max_bytes)
              rescue ArgumentError, TypeError
                nil
              end
            max_bytes ||= TavernKit::VibeTavern::Directives::Parser::DEFAULT_MAX_BYTES

            parsed =
              TavernKit::VibeTavern::Directives::Parser.parse_json(
                assistant_message.fetch("content", nil),
                max_bytes: max_bytes,
              )

            if parsed[:ok]
              validated =
                TavernKit::VibeTavern::Directives::Validator.validate(
                  parsed[:value],
                  allowed_types: allowed_types,
                  type_aliases: type_aliases,
                  payload_validator: payload_validator,
                )
              if validated[:ok]
                structured_output = validated[:value]
                structured_output_warnings = validated[:warnings]
              else
                structured_output_error = validated
              end
            else
              structured_output_error = parsed
            end
          end
        end

        if output_tags_enabled && structured_output.is_a?(Hash) && structured_output.key?("assistant_text")
          transformed = structured_output.dup
          transformed["assistant_text"] =
            TavernKit::VibeTavern::OutputTags.transform(
              structured_output.fetch("assistant_text", nil),
              runtime: runtime,
            )
          structured_output = transformed
        end

        PromptResult.new(
          prompt_request: prompt_request,
          response: response,
          body: body,
          assistant_message: assistant_message,
          finish_reason: body.dig("choices", 0, "finish_reason"),
          elapsed_ms: elapsed_ms,
          structured_output: structured_output,
          structured_output_error: structured_output_error,
          structured_output_warnings: structured_output_warnings,
        )
      end

      def perform_stream(prompt_request, include_usage: true, &on_delta)
        prompt_request = prompt_request.is_a?(PromptRequest) ? prompt_request : nil
        raise ArgumentError, "prompt_request is required" unless prompt_request

        if prompt_request.structured_output_kind
          raise ArgumentError, "PromptRunner#perform_stream does not support structured outputs; use #perform instead"
        end

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
            runtime: prompt_request.runtime,
          )
        end

        runtime = prompt_request.runtime
        if runtime && TavernKit::VibeTavern::OutputTags.enabled?(runtime)
          assistant_message["content"] =
            TavernKit::VibeTavern::OutputTags.transform(
              assistant_message.fetch("content", nil),
              runtime: runtime,
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
        h = value.is_a?(Hash) ? TavernKit::Utils.deep_symbolize_keys(value) : {}

        # Streaming is an execution mode, not a request option in this layer.
        # Use PromptRunner#perform_stream for streaming chat-only runs.
        if h.key?(:stream) || h.key?(:stream_options)
          raise ArgumentError, "streaming is not supported via llm_options; use PromptRunner#perform_stream instead"
        end

        h.delete(:model)
        h.delete(:messages)
        h
      end

      def normalize_llm_options_defaults(value)
        h = normalize_llm_options(value)
        h.delete(:tools)
        h.delete(:tool_choice)
        h.delete(:response_format)
        h
      end

      def normalize_runtime(value)
        return nil if value.nil?
        return value unless value.is_a?(Hash)

        TavernKit::Runtime::Base.build(value, type: :app)
      rescue StandardError
        nil
      end

      def deep_merge_hashes(left, right)
        out = (left.is_a?(Hash) ? left : {}).dup
        (right.is_a?(Hash) ? right : {}).each do |k, v|
          if out[k].is_a?(Hash) && v.is_a?(Hash)
            out[k] = deep_merge_hashes(out[k], v)
          else
            out[k] = v
          end
        end
        out
      end
    end
  end
end
