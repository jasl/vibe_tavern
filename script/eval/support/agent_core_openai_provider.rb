# frozen_string_literal: true

require "json"

require "agent_core"

require_relative "tool_call_tags"

module VibeTavernEval
  # Eval-only OpenAI-compatible provider wrapper for AgentCore.
  #
  # Why this exists:
  # - Keep eval scripts standalone (no Rails boot)
  # - Allow opt-in provider/model workarounds (reasoning_content/signature)
  # - Allow opt-in text-tag tool-call fallback (<tool_call>...</tool_call>)
  # - Allow per-run tool-args max-bytes (for guardrail eval cases)
  class AgentCoreOpenAIProvider < AgentCore::Resources::Provider::Base
    MESSAGE_TRANSFORMS = %i[
      assistant_tool_calls_reasoning_content_empty_if_missing
      assistant_tool_calls_signature_skip_validator_if_missing
    ].freeze

    def initialize(
      client:,
      request_defaults: {},
      stream_include_usage: true,
      message_transforms: [],
      enable_tool_call_tag_fallback: false,
      max_tool_args_bytes: AgentCore::Utils::DEFAULT_MAX_TOOL_ARGS_BYTES
    )
      @client = client
      @request_defaults = normalize_request_defaults(request_defaults)
      @stream_include_usage = stream_include_usage == true
      @message_transforms = normalize_message_transforms(message_transforms)
      @enable_tool_call_tag_fallback = enable_tool_call_tag_fallback == true
      @max_tool_args_bytes = normalize_max_tool_args_bytes(max_tool_args_bytes)
    end

    def name = "eval_openai_compatible"

    def chat(messages:, model:, tools: nil, stream: false, **options)
      raise ArgumentError, "streaming is not supported in eval provider" if stream

      require "simple_inference"

      model_name = model.to_s.strip
      raise ArgumentError, "model is required" if model_name.empty?

      request_messages = build_openai_messages(messages)
      request_tools = tools.nil? || tools.empty? ? nil : build_openai_tools(tools)

      request = { model: model_name, messages: request_messages }
      request[:tools] = request_tools if request_tools

      request_options = @request_defaults.merge(sanitize_options(options))
      if request_tools && !request_options.key?(:parallel_tool_calls)
        request_options[:parallel_tool_calls] = false
      end

      response = @client.chat_completions(**request.merge(request_options))
      body = response.body.is_a?(Hash) ? response.body : {}

      message, stop_reason = message_from_openai_body(body)
      usage = usage_from_openai_body(body)

      AgentCore::Resources::Provider::Response.new(
        message: message,
        usage: usage,
        raw: body,
        stop_reason: stop_reason,
      )
    end

    private

    def normalize_request_defaults(value)
      return {} if value.nil?
      raise ArgumentError, "request_defaults must be a Hash" unless value.is_a?(Hash)

      AgentCore::Utils.deep_symbolize_keys(value)
    end

    def normalize_message_transforms(value)
      Array(value).filter_map do |name|
        sym = name.to_s.strip.downcase.tr("-", "_").to_sym
        next unless MESSAGE_TRANSFORMS.include?(sym)

        sym
      end.uniq
    end

    def normalize_max_tool_args_bytes(value)
      bytes = Integer(value)
      raise ArgumentError, "max_tool_args_bytes must be positive" if bytes <= 0
      bytes
    rescue ArgumentError, TypeError
      AgentCore::Utils::DEFAULT_MAX_TOOL_ARGS_BYTES
    end

    def sanitize_options(options)
      out = AgentCore::Utils.deep_symbolize_keys(options)
      out.delete(:stream)
      out
    end

    def message_from_openai_body(body)
      choice0 = body.dig("choices", 0)
      choice0 = {} unless choice0.is_a?(Hash)

      msg = choice0.fetch("message", nil)
      msg = {} unless msg.is_a?(Hash)

      content, tool_calls = content_and_tool_calls_from_openai_message(msg)

      message = AgentCore::Message.new(role: :assistant, content: content, tool_calls: tool_calls.empty? ? nil : tool_calls)
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

      AgentCore::Resources::Provider::Usage.new(
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

    def content_and_tool_calls_from_openai_message(msg)
      require "simple_inference"

      content = ::SimpleInference::OpenAI.normalize_content(msg.fetch("content", nil)).to_s
      tool_calls = tool_calls_from_openai_message(msg)

      if tool_calls.empty? && @enable_tool_call_tag_fallback
        extracted = VibeTavernEval::ToolCallTags.extract(content)
        tagged_calls = extracted.fetch(:tool_calls)

        if tagged_calls.any?
          content = extracted.fetch(:content).to_s
          tool_calls = tool_calls_from_openai_tool_calls(tagged_calls)
        end
      end

      [content, tool_calls]
    end

    def tool_calls_from_openai_message(msg)
      h = AgentCore::Utils.symbolize_keys(msg)

      tool_calls_raw = h.fetch(:tool_calls, nil)
      tool_calls =
        case tool_calls_raw
        when Array then tool_calls_raw
        when Hash then [tool_calls_raw]
        else []
        end

      parsed = tool_calls_from_openai_tool_calls(tool_calls)
      return parsed unless parsed.empty?

      fc_raw = h.fetch(:function_call, nil)
      return [] unless fc_raw.is_a?(Hash)

      fc = AgentCore::Utils.symbolize_keys(fc_raw)
      name = fc.fetch(:name, nil).to_s.strip
      return [] if name.empty?

      args_hash, parse_error = AgentCore::Utils.parse_tool_arguments(fc.fetch(:arguments, nil), max_bytes: @max_tool_args_bytes)

      [AgentCore::ToolCall.new(id: "tc_1", name: name, arguments: args_hash, arguments_parse_error: parse_error)]
    end

    def tool_calls_from_openai_tool_calls(tool_calls)
      tool_calls
        .filter_map { |tc_raw| normalize_openai_tool_call(tc_raw) }
        .map
        .with_index do |data, idx|
          AgentCore::ToolCall.new(
            id: normalize_tool_call_id(data.fetch(:id), fallback: "tc_#{idx + 1}"),
            name: data.fetch(:name),
            arguments: data.fetch(:arguments),
            arguments_parse_error: data.fetch(:arguments_parse_error),
          )
        end
    end

    def normalize_openai_tool_call(value)
      return nil unless value.is_a?(Hash)

      tc = AgentCore::Utils.symbolize_keys(value)
      fn = AgentCore::Utils.symbolize_keys(tc.fetch(:function, nil))

      name = fn.fetch(:name, nil).to_s.strip
      return nil if name.empty?

      args_hash, parse_error = AgentCore::Utils.parse_tool_arguments(fn.fetch(:arguments, nil), max_bytes: @max_tool_args_bytes)

      {
        id: tc.fetch(:id, nil).to_s.strip,
        name: name,
        arguments: args_hash,
        arguments_parse_error: parse_error,
      }
    end
    private :normalize_openai_tool_call

    def normalize_tool_call_id(value, fallback:)
      base_id = value.to_s.strip
      base_id = fallback.to_s if base_id.empty?
      base_id = "tc_1" if base_id.strip.empty?

      @used_tool_call_ids ||= {}
      AgentCore::Utils.normalize_tool_call_id(base_id, used: @used_tool_call_ids, fallback: fallback)
    end

    def build_openai_messages(messages)
      Array(messages).map do |msg|
        raise ArgumentError, "messages must contain AgentCore::Message instances" unless msg.is_a?(AgentCore::Message)

        role = openai_role(msg.role)
        out = { "role" => role }

        if role == "tool"
          out["tool_call_id"] = msg.tool_call_id.to_s if msg.tool_call_id
          out["content"] = msg.text.to_s
          next out
        end

        out["content"] = openai_content(msg)

        if role == "assistant" && msg.has_tool_calls?
          tool_calls = msg.tool_calls.map { |tc| openai_tool_call(tc) }
          apply_tool_call_transforms!(tool_calls)
          out["tool_calls"] = tool_calls

          out["reasoning_content"] = "" if reasoning_content_empty_if_missing?

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
      when AgentCore::TextContent
        { "type" => "text", "text" => block.text.to_s }
      when AgentCore::ImageContent
        { "type" => "image_url", "image_url" => { "url" => openai_image_url(block) } }
      when AgentCore::DocumentContent
        { "type" => "text", "text" => document_placeholder(block) }
      when AgentCore::AudioContent
        { "type" => "text", "text" => audio_placeholder(block) }
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

    def apply_tool_call_transforms!(tool_calls)
      return unless signature_skip_validator_if_missing?

      tool_calls.each do |tc|
        next unless tc.is_a?(Hash)
        next if tc.key?("signature")

        tc["signature"] = "skip_thought_signature_validator"
      end
    end

    def reasoning_content_empty_if_missing?
      @message_transforms.include?(:assistant_tool_calls_reasoning_content_empty_if_missing)
    end

    def signature_skip_validator_if_missing?
      @message_transforms.include?(:assistant_tool_calls_signature_skip_validator_if_missing)
    end

    def build_openai_tools(tools)
      Array(tools).map do |tool|
        raise ArgumentError, "tools must contain Hash definitions" unless tool.is_a?(Hash)

        h = AgentCore::Utils.symbolize_keys(tool)

        name = ""
        description = ""
        parameters = {}

        if h[:type].to_s == "function" && h[:function].is_a?(Hash)
          fn = AgentCore::Utils.symbolize_keys(h.fetch(:function))
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
        parameters = AgentCore::Utils.normalize_json_schema(parameters)

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
  end
end
