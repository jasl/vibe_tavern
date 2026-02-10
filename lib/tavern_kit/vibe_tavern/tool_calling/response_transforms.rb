# frozen_string_literal: true

require "json"

module TavernKit
  module VibeTavern
    module ToolCalling
      # Provider/model compatibility shims applied to inbound OpenAI-style response
      # message hashes.
      #
      # These transforms are applied to the assistant message hash extracted from
      # the provider response (`choices[0].message`), before ToolLoopRunner parses
      # `content` and `tool_calls`.
      module ResponseTransforms
        REGISTRY = {}

        module_function

        def register(name, callable = nil, &block)
          transform = callable || block
          raise ArgumentError, "transform must respond to #call" unless transform&.respond_to?(:call)

          canonical = canonical_name(name)
          raise ArgumentError, "transform name is required" if canonical.empty?

          REGISTRY[canonical] = transform
        end

        def apply!(assistant_message, transforms, strict: false, output_tags_config: nil)
          return unless assistant_message.is_a?(Hash)

          Array(transforms).each do |name|
            canonical = canonical_name(name)
            next if canonical.empty?

            transform = REGISTRY[canonical]
            if transform
              call_transform(transform, assistant_message, output_tags_config)
            elsif strict
              raise ArgumentError, "Unknown response transform: #{name}"
            end
          end
        end

        def canonical_name(name)
          name.to_s.strip.downcase.tr("-", "_")
        end
        private_class_method :canonical_name

        def call_transform(transform, assistant_message, output_tags_config)
          return transform.call(assistant_message) if output_tags_config.nil?

          params = transform.respond_to?(:parameters) ? transform.parameters : []
          accepts_output_tags_keyword =
            params.any? do |type, name|
              type == :keyrest || (%i[key keyreq].include?(type) && name == :output_tags_config)
            end

          if accepts_output_tags_keyword
            transform.call(assistant_message, output_tags_config: output_tags_config)
          elsif transform.arity == 2
            transform.call(assistant_message, output_tags_config)
          else
            transform.call(assistant_message)
          end
        end
        private_class_method :call_transform
      end
    end
  end
end

TavernKit::VibeTavern::ToolCalling::ResponseTransforms.register(
  "assistant_function_call_to_tool_calls",
  lambda do |msg|
    tool_calls = msg.fetch("tool_calls", nil)
    return if tool_calls.is_a?(Array) && tool_calls.any?

    fc = msg.fetch("function_call", nil)
    return unless fc.is_a?(Hash)

    name = fc.fetch("name", "").to_s
    return if name.strip.empty?

    args = fc.key?("arguments") ? fc.fetch("arguments") : nil
    args = JSON.generate(args) if args.is_a?(Hash) || args.is_a?(Array)

    msg["tool_calls"] = [
      {
        "id" => "call_1",
        "type" => "function",
        "function" => {
          "name" => name,
          "arguments" => args.to_s,
        },
      },
    ]
  end,
)

TavernKit::VibeTavern::ToolCalling::ResponseTransforms.register(
  "assistant_tool_calls_object_to_array",
  lambda do |msg|
    tool_calls = msg.fetch("tool_calls", nil)
    return unless tool_calls.is_a?(Hash)

    msg["tool_calls"] = [tool_calls]
  end,
)

TavernKit::VibeTavern::ToolCalling::ResponseTransforms.register(
  "assistant_tool_calls_arguments_json_string_if_hash",
  lambda do |msg|
    tool_calls = msg.fetch("tool_calls", nil)
    return unless tool_calls.is_a?(Array) && tool_calls.any?

    tool_calls.each do |tc|
      next unless tc.is_a?(Hash)

      fn = tc.fetch("function", nil)
      next unless fn.is_a?(Hash)

      args = fn.fetch("arguments", nil)
      next unless args.is_a?(Hash) || args.is_a?(Array)

      fn["arguments"] = JSON.generate(args)
    end
  end,
)

extract_tool_call_from_tag_payload =
  lambda do |payload, index|
    raw = payload.to_s.strip
    return nil if raw.empty?

    name = nil
    args = nil

    begin
      parsed = JSON.parse(raw)
      if parsed.is_a?(Hash)
        if parsed["function"].is_a?(Hash)
          fn = parsed["function"]
          name = fn["name"].to_s.strip
          args = fn.key?("arguments") ? fn["arguments"] : nil
        else
          name = parsed["name"].to_s.strip
          args = parsed.key?("arguments") ? parsed["arguments"] : parsed["args"]
        end
      end
    rescue JSON::ParserError
      # Fallback: allow `tool_name {json}` / `tool_name` forms.
      if (m = raw.match(/\A([a-zA-Z0-9_.-]+)\s+(\{.*\})\z/m))
        name = m.fetch(1).to_s.strip
        args = m.fetch(2).to_s
      else
        name = raw if raw.match?(/\A[a-zA-Z0-9_.-]+\z/)
      end
    end

    return nil if name.to_s.empty?

    arguments =
      case args
      when nil
        "{}"
      when String
        args
      when Hash, Array
        JSON.generate(args)
      else
        "{}"
      end

    {
      "id" => "tag_call_#{index}",
      "type" => "function",
      "function" => {
        "name" => name,
        "arguments" => arguments,
      },
    }
  end

TavernKit::VibeTavern::ToolCalling::ResponseTransforms.register(
  "assistant_content_tool_call_tags_to_tool_calls",
  lambda do |msg, output_tags_config: nil|
    tool_calls = msg.fetch("tool_calls", nil)
    return if tool_calls.is_a?(Array) && tool_calls.any?
    return if tool_calls.is_a?(Hash) && tool_calls.any?

    content = msg.fetch("content", nil)
    return unless content.is_a?(String)
    return unless content.include?("<tool_call>")

    escape_hatch_cfg = output_tags_config&.escape_hatch

    masked, placeholders =
      TavernKit::Text::VerbatimMasker.mask(
        content,
        escape_hatch: escape_hatch_cfg,
      )

    tagged = masked.scan(/<tool_call>(.*?)<\/tool_call>/m).flatten
    if tagged.empty?
      msg["content"] = TavernKit::Text::VerbatimMasker.unmask(masked, placeholders)
      return
    end

    parsed =
      tagged.each_with_index.filter_map do |payload, idx|
        extract_tool_call_from_tag_payload.call(payload, idx + 1)
      end
    if parsed.empty?
      msg["content"] = TavernKit::Text::VerbatimMasker.unmask(masked, placeholders)
      return
    end

    msg["tool_calls"] = parsed

    cleaned_masked = masked.gsub(/<tool_call>.*?<\/tool_call>/m, "").strip
    msg["content"] = TavernKit::Text::VerbatimMasker.unmask(cleaned_masked, placeholders)
  end,
)
