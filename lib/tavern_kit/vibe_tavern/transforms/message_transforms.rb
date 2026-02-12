# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module Transforms
      # Provider/model compatibility shims applied to outbound OpenAI-style messages.
      #
      # Context stores only transform *names* so it stays serializable and can be
      # merged via presets. Upper layers can register additional transforms if
      # needed.
      module MessageTransforms
        REGISTRY = {}

        module_function

        def register(name, callable = nil, &block)
          transform = callable || block
          raise ArgumentError, "transform must respond to #call" unless transform&.respond_to?(:call)

          canonical = canonical_name(name)
          raise ArgumentError, "transform name is required" if canonical.empty?

          REGISTRY[canonical] = transform
        end

        def apply!(messages, transforms, strict: false)
          return unless messages.is_a?(Array)

          Array(transforms).each do |name|
            canonical = canonical_name(name)
            next if canonical.empty?

            transform = REGISTRY[canonical]
            if transform
              transform.call(messages)
            elsif strict
              raise ArgumentError, "Unknown message transform: #{name}"
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

TavernKit::VibeTavern::Transforms::MessageTransforms.register(
  "assistant_tool_calls_content_null_if_blank",
  lambda do |messages|
    messages.each do |msg|
      next unless msg.is_a?(Hash)

      role = msg.fetch(:role, "")
      next unless role == "assistant"

      tool_calls = msg.fetch(:tool_calls, nil)
      next unless tool_calls.is_a?(Array) && tool_calls.any?

      content = msg.fetch(:content, nil)
      next unless content.is_a?(String)
      next unless content.strip.empty?

      msg[:content] = nil
    end
  end,
)

reasoning_content_empty =
  lambda do |messages|
    messages.each do |msg|
      next unless msg.is_a?(Hash)

      role = msg.fetch(:role, "")
      next unless role == "assistant"

      tool_calls = msg.fetch(:tool_calls, nil)
      next unless tool_calls.is_a?(Array) && tool_calls.any?

      next if msg.key?(:reasoning_content)

      # Provider extension field (not part of the canonical OpenAI message shape).
      msg[:reasoning_content] = ""
    end
  end

TavernKit::VibeTavern::Transforms::MessageTransforms.register(
  "assistant_tool_calls_reasoning_content_empty_if_missing",
  reasoning_content_empty,
)

TavernKit::VibeTavern::Transforms::MessageTransforms.register(
  "assistant_tool_calls_signature_skip_validator_if_missing",
  lambda do |messages|
    messages.each do |msg|
      next unless msg.is_a?(Hash)

      role = msg.fetch(:role, "")
      next unless role == "assistant"

      tool_calls = msg.fetch(:tool_calls, nil)
      next unless tool_calls.is_a?(Array) && tool_calls.any?

      tool_calls.each do |tc|
        next unless tc.is_a?(Hash)
        next if tc.key?(:signature)

        tc[:signature] = "skip_thought_signature_validator"
      end
    end
  end,
)
