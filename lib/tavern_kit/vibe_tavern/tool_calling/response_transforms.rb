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

        def apply!(assistant_message, transforms, strict: false)
          return unless assistant_message.is_a?(Hash)

          Array(transforms).each do |name|
            canonical = canonical_name(name)
            next if canonical.empty?

            transform = REGISTRY[canonical]
            if transform
              transform.call(assistant_message)
            elsif strict
              raise ArgumentError, "Unknown response transform: #{name}"
            end
          end
        end

        def canonical_name(name)
          name.to_s.strip.downcase.tr("-", "_")
        end
        private_class_method :canonical_name
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
