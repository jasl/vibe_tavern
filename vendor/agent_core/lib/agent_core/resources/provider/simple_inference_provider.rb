# frozen_string_literal: true

require "json"

module AgentCore
  module Resources
    module Provider
      # Optional Provider implementation built on SimpleInference (OpenAI-compatible).
      #
      # This is a soft dependency and is only loaded/required when used.
      #
      # @example
      #   require "agent_core"
      #   require "agent_core/resources/provider/simple_inference_provider"
      #
      #   provider = AgentCore::Resources::Provider::SimpleInferenceProvider.new(
      #     base_url: "https://api.openai.com",
      #     api_key: ENV["OPENAI_API_KEY"],
      #   )
      class SimpleInferenceProvider < Base
        def initialize(client: nil, stream_include_usage: true, request_defaults: {}, **client_options)
          @client = client
          @client_options = client_options
          @stream_include_usage = stream_include_usage == true
          @request_defaults = normalize_request_defaults(request_defaults)
        end

        def name = "simple_inference"

        def chat(messages:, model:, tools: nil, stream: false, **options)
          model_name = model.to_s.strip
          raise ArgumentError, "model is required" if model_name.empty?

          client = ensure_client!

          request_messages = build_openai_messages(messages)
          request_tools = tools.nil? || tools.empty? ? nil : build_openai_tools(tools)

          request = { model: model_name, messages: request_messages }
          request[:tools] = request_tools if request_tools

          request_options = @request_defaults.merge(sanitize_options(options))

          if request_tools && !request_options.key?(:parallel_tool_calls)
            request_options[:parallel_tool_calls] = false
          end

          if stream
            stream_chat(client: client, request: request, options: request_options)
          else
            sync_chat(client: client, request: request, options: request_options)
          end
        end

        private

        def ensure_client!
          return @client if @client

          require_simple_inference!
          @client = ::SimpleInference::Client.new(**@client_options)
        end

        def require_simple_inference!
          return if defined?(::SimpleInference::Client)

          require "simple_inference"
        rescue LoadError => e
          raise LoadError,
                "The 'simple_inference' gem is required for AgentCore::Resources::Provider::SimpleInferenceProvider. " \
                "Add `gem \"simple_inference\"` to your Gemfile.",
                cause: e
        end

        def sanitize_options(options)
          out = Utils.symbolize_keys(options)
          out.delete(:stream)
          out
        end

        def normalize_request_defaults(value)
          return {} if value.nil?
          raise ArgumentError, "request_defaults must be a Hash" unless value.is_a?(Hash)

          Utils.deep_symbolize_keys(value)
        end

        def sync_chat(client:, request:, options:)
          require_simple_inference!

          response = client.chat_completions(**request.merge(options))
          body = response.body.is_a?(Hash) ? response.body : {}

          message, stop_reason = message_from_openai_body(body)
          usage = usage_from_openai_body(body)

          Resources::Provider::Response.new(
            message: message,
            usage: usage,
            raw: body,
            stop_reason: stop_reason
          )
        rescue ::SimpleInference::Errors::HTTPError => e
          raise ProviderError.new(e.message, status: e.status, body: e.body)
        rescue ::SimpleInference::Errors::Error => e
          raise ProviderError, e.message
        end

        def stream_chat(client:, request:, options:)
          require_simple_inference!

          stream_options = options.fetch(:stream_options, nil)
          stream_options = Utils.deep_symbolize_keys(stream_options) if stream_options.is_a?(Hash)

          if @stream_include_usage && (stream_options.nil? || stream_options.is_a?(Hash))
            stream_options ||= {}
            stream_options[:include_usage] = true unless stream_options.key?(:include_usage)
          end

          stream_request = request.merge(options)
          stream_request[:stream_options] = stream_options if stream_options

          Enumerator.new do |y|
            content = +""
            finish_reason = nil
            last_usage = nil

            tool_states = {}
            tool_started = {}
            used_tool_call_ids = {}

            client.chat_completions_stream(**stream_request) do |event|
              delta = ::SimpleInference::OpenAI.chat_completion_chunk_delta(event)
              if delta
                content << delta
                y << StreamEvent::TextDelta.new(text: delta)
              end

              choice0 = event.is_a?(Hash) ? event.dig("choices", 0) : nil
              fr = choice0.is_a?(Hash) ? choice0["finish_reason"] : nil
              finish_reason = fr if fr

              usage = event.is_a?(Hash) ? event["usage"] : nil
              last_usage = usage if usage.is_a?(Hash)

              delta_hash = choice0.is_a?(Hash) ? choice0["delta"] : nil
              tool_deltas = delta_hash.is_a?(Hash) ? delta_hash["tool_calls"] : nil

              each_tool_call_delta(tool_deltas) do |idx, id, name, arguments_delta|
                state = tool_states[idx] ||= { id: nil, name: nil, arguments: +"" }
                state[:id] ||=
                  Utils.normalize_tool_call_id(
                    id,
                    used: used_tool_call_ids,
                    fallback: "tc_#{idx + 1}",
                  )
                state[:name] ||= name if name

                if state[:id] && state[:name] && !tool_started[state[:id]]
                  tool_started[state[:id]] = true
                  y << StreamEvent::ToolCallStart.new(id: state[:id], name: state[:name])
                end

                if arguments_delta
                  state[:arguments] << arguments_delta
                  y << StreamEvent::ToolCallDelta.new(id: state[:id], arguments_delta: arguments_delta) if state[:id]
                end
              end
            end

            tool_calls = build_tool_calls_from_states(tool_states)
            tool_calls.each do |tc|
              y << StreamEvent::ToolCallEnd.new(id: tc.id, name: tc.name, arguments: tc.arguments)
            end

            message = Message.new(role: :assistant, content: content, tool_calls: tool_calls.empty? ? nil : tool_calls)
            stop_reason = stop_reason_from_finish_reason(finish_reason)
            usage_obj = usage_from_openai_usage(last_usage)

            y << StreamEvent::MessageComplete.new(message: message)
            y << StreamEvent::Done.new(stop_reason: stop_reason, usage: usage_obj)
          rescue ::SimpleInference::Errors::Error => e
            y << StreamEvent::ErrorEvent.new(error: e.message, recoverable: false)
          rescue StandardError => e
            y << StreamEvent::ErrorEvent.new(error: "#{e.class}: #{e.message}", recoverable: false)
          end
        end

        def message_from_openai_body(body)
          choice0 = body.dig("choices", 0)
          choice0 = {} unless choice0.is_a?(Hash)

          msg = choice0.fetch("message", nil)
          msg = {} unless msg.is_a?(Hash)

          content = ::SimpleInference::OpenAI.normalize_content(msg.fetch("content", nil)).to_s
          tool_calls = tool_calls_from_openai_message(msg)

          message = Message.new(role: :assistant, content: content, tool_calls: tool_calls.empty? ? nil : tool_calls)
          stop_reason = stop_reason_from_finish_reason(choice0.fetch("finish_reason", nil))

          [message, stop_reason]
        end

        def usage_from_openai_body(body)
          usage_hash = body.fetch("usage", nil)
          usage_from_openai_usage(usage_hash)
        end

        def usage_from_openai_usage(usage_hash)
          return nil unless usage_hash.is_a?(Hash)

          input_tokens = Integer(usage_hash.fetch("prompt_tokens", 0), exception: false) || 0
          output_tokens = Integer(usage_hash.fetch("completion_tokens", 0), exception: false) || 0

          cached_tokens =
            begin
              details = usage_hash.fetch("prompt_tokens_details", nil)
              details.is_a?(Hash) ? details.fetch("cached_tokens", nil) : nil
            rescue StandardError
              nil
            end
          cache_read_tokens = Integer(cached_tokens, exception: false) || 0

          Resources::Provider::Usage.new(
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            cache_read_tokens: cache_read_tokens,
          )
        end

        def stop_reason_from_finish_reason(value)
          case value.to_s
          when "tool_calls" then :tool_use
          when "function_call" then :tool_use
          when "length" then :max_tokens
          when "stop_sequence" then :stop_sequence
          else :end_turn
          end
        end

        def tool_calls_from_openai_message(msg)
          h = Utils.symbolize_keys(msg)

          tool_calls_raw = h.fetch(:tool_calls, nil)
          tool_calls =
            case tool_calls_raw
            when Array then tool_calls_raw
            when Hash then [tool_calls_raw]
            else []
            end

          parsed = []

          tool_calls.each do |tc_raw|
            next unless tc_raw.is_a?(Hash)

            tc = Utils.symbolize_keys(tc_raw)
            fn = Utils.symbolize_keys(tc.fetch(:function, nil))

            name = fn.fetch(:name, nil).to_s.strip
            next if name.empty?

            args_hash, parse_error = Utils.parse_tool_arguments(fn.fetch(:arguments, nil))

            parsed << {
              id: tc.fetch(:id, nil).to_s.strip,
              name: name,
              arguments: args_hash,
              arguments_parse_error: parse_error,
            }
          end

          if parsed.empty?
            fc_raw = h.fetch(:function_call, nil)
            if fc_raw.is_a?(Hash)
              fc = Utils.symbolize_keys(fc_raw)
              name = fc.fetch(:name, nil).to_s.strip
              unless name.empty?
                args_hash, parse_error = Utils.parse_tool_arguments(fc.fetch(:arguments, nil))
                parsed << { id: "", name: name, arguments: args_hash, arguments_parse_error: parse_error }
              end
            end
          end

          used = {}

          parsed.map.with_index do |data, idx|
            id =
              Utils.normalize_tool_call_id(
                data.fetch(:id),
                used: used,
                fallback: "tc_#{idx + 1}",
              )

            ToolCall.new(
              id: id,
              name: data.fetch(:name),
              arguments: data.fetch(:arguments),
              arguments_parse_error: data.fetch(:arguments_parse_error),
            )
          end
        end

        def build_openai_messages(messages)
          Array(messages).map do |msg|
            unless msg.is_a?(Message)
              raise ArgumentError, "messages must contain AgentCore::Message instances"
            end

            role = openai_role(msg.role)

            out = { "role" => role }

            if role == "tool"
              out["tool_call_id"] = msg.tool_call_id.to_s if msg.tool_call_id
              out["content"] = msg.text.to_s
              next out
            end

            out["content"] = openai_content(msg)

            if role == "assistant" && msg.has_tool_calls?
              out["tool_calls"] = msg.tool_calls.map { |tc| openai_tool_call(tc) }
              if out["content"].is_a?(String) && out["content"].strip.empty?
                out["content"] = nil
              end
            end

            out
          end
        end

        def openai_role(role)
          case role
          when :system then "system"
          when :user then "user"
          when :assistant then "assistant"
          when :tool_result then "tool"
          else
            raise ArgumentError, "Unsupported message role: #{role.inspect}"
          end
        end

        def openai_content(msg)
          case msg.content
          when String
            msg.content
          when Array
            parts = msg.content.filter_map { |block| openai_part(block) }

            all_text = parts.all? { |p| p["type"] == "text" }
            return parts.map { |p| p["text"].to_s }.join if all_text

            parts
          when nil
            ""
          else
            msg.content.to_s
          end
        end

        def openai_part(block)
          case block
          when TextContent
            { "type" => "text", "text" => block.text.to_s }
          when ImageContent
            { "type" => "image_url", "image_url" => { "url" => openai_image_url(block) } }
          when DocumentContent
            { "type" => "text", "text" => document_placeholder(block) }
          when AudioContent
            { "type" => "text", "text" => audio_placeholder(block) }
          when ToolUseContent, ToolResultContent
            { "type" => "text", "text" => block.to_h.to_s }
          else
            { "type" => "text", "text" => block.to_s }
          end
        end

        def openai_image_url(block)
          case block.source_type
          when :url
            block.url.to_s
          when :base64
            mime = block.media_type.to_s
            data = block.data.to_s
            "data:#{mime};base64,#{data}"
          else
            ""
          end
        end

        def document_placeholder(block)
          mime = block.effective_media_type
          case block.source_type
          when :url
            "[document: #{mime || "unknown"} url=#{block.url}]"
          when :base64
            "[document: #{mime || "unknown"} base64]"
          else
            "[document]"
          end
        end

        def audio_placeholder(block)
          mime = block.effective_media_type
          transcript = block.respond_to?(:transcript) ? block.transcript.to_s : ""
          suffix = transcript.strip.empty? ? "" : " transcript=#{transcript.inspect}"

          case block.source_type
          when :url
            "[audio: #{mime || "unknown"} url=#{block.url}#{suffix}]"
          when :base64
            "[audio: #{mime || "unknown"} base64#{suffix}]"
          else
            "[audio#{suffix}]"
          end
        end

        def openai_tool_call(tc)
          args = tc.respond_to?(:arguments) ? (tc.arguments || {}) : {}

          {
            "id" => tc.id.to_s,
            "type" => "function",
            "function" => {
              "name" => tc.name.to_s,
              "arguments" => JSON.generate(args),
            },
          }
        end

        def build_openai_tools(tools)
          Array(tools).map do |tool|
            raise ArgumentError, "tools must contain Hash definitions" unless tool.is_a?(Hash)

            h = Utils.symbolize_keys(tool)

            name = ""
            description = ""
            parameters = {}

            if h[:type].to_s == "function" && h[:function].is_a?(Hash)
              fn = Utils.symbolize_keys(h.fetch(:function))
              name = fn.fetch(:name, "").to_s
              description = fn.fetch(:description, "").to_s
              parameters = fn.fetch(:parameters, {})
            else
              name = h.fetch(:name, "").to_s
              description = h.fetch(:description, "").to_s
              parameters = h.fetch(:parameters, {})
            end

            raise ArgumentError, "tool name is required" if name.strip.empty?

            parameters = {} unless parameters.is_a?(Hash)
            parameters = Utils.normalize_json_schema(parameters)

            {
              "type" => "function",
              "function" => {
                "name" => name,
                "description" => description,
                "parameters" => parameters,
              },
            }
          end.compact
        end

        def each_tool_call_delta(tool_deltas)
          Array(tool_deltas).each do |tc|
            next unless tc.is_a?(Hash)

            idx = Integer(tc.fetch("index", nil), exception: false)
            next if idx.nil? || idx < 0

            id = tc.fetch("id", nil)&.to_s
            fn = tc.fetch("function", nil)
            fn = {} unless fn.is_a?(Hash)

            name = fn.fetch("name", nil)&.to_s
            args_delta = fn.fetch("arguments", nil)

            yield idx, (id&.strip&.empty? ? nil : id), (name&.strip&.empty? ? nil : name), (args_delta.nil? ? nil : args_delta.to_s)
          end
        end

        def build_tool_calls_from_states(tool_states)
          tool_states
            .sort_by { |idx, _| idx }
            .filter_map do |idx, state|
              id = state.fetch(:id, nil).to_s.strip
              name = state.fetch(:name, nil).to_s.strip
              args = state.fetch(:arguments, "").to_s

              next if name.empty?

              id = "tc_#{idx + 1}" if id.empty?

              args_hash, parse_error = Utils.parse_tool_arguments(args)
              ToolCall.new(id: id, name: name, arguments: args_hash, arguments_parse_error: parse_error)
            end
        end
      end
    end
  end
end
