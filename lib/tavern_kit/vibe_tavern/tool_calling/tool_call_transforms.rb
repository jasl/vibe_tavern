# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolCalling
      # Provider/model compatibility shims applied to parsed tool calls, before
      # execution.
      #
      # The runner parses tool calls into an Array<Hash> with symbol keys:
      #   { id:, type:, function: { name:, arguments: ... } }
      #
      # Runtime stores only transform *names* so it stays serializable and can be
      # merged via presets. Upper layers can register additional transforms if
      # needed.
      module ToolCallTransforms
        REGISTRY = {}

        module_function

        def register(name, callable = nil, &block)
          transform = callable || block
          raise ArgumentError, "transform must respond to #call" unless transform&.respond_to?(:call)

          canonical = canonical_name(name)
          raise ArgumentError, "transform name is required" if canonical.empty?

          REGISTRY[canonical] = transform
        end

        # Applies named transforms to a tool_calls array.
        #
        # Each transform receives a mutable Array of tool call hashes and may
        # mutate it in place. If the transform returns an Array, the returned
        # Array becomes the new working set for subsequent transforms.
        def apply(tool_calls, transforms, strict: false)
          current = Array(tool_calls).map { |tc| deep_symbolize_keys(tc) }

          Array(transforms).each do |name|
            canonical = canonical_name(name)
            next if canonical.empty?

            transform = REGISTRY[canonical]
            if transform
              result = transform.call(current)
              if result.is_a?(Array)
                current = result.map { |tc| deep_symbolize_keys(tc) }
              end
            elsif strict
              raise ArgumentError, "Unknown tool call transform: #{name}"
            end
          end

          current
        end

        def canonical_name(name)
          name.to_s.strip.downcase.tr("-", "_")
        end
        private_class_method :canonical_name

        def deep_symbolize_keys(value)
          case value
          when Hash
            value.each_with_object({}) do |(k, v), out|
              if k.is_a?(Symbol)
                out[k] = deep_symbolize_keys(v)
              else
                sym = k.to_s.to_sym
                out[sym] = deep_symbolize_keys(v) unless out.key?(sym)
              end
            end
          when Array
            value.map { |v| deep_symbolize_keys(v) }
          else
            value
          end
        end
        private_class_method :deep_symbolize_keys
      end
    end
  end
end

TavernKit::VibeTavern::ToolCalling::ToolCallTransforms.register(
  "assistant_tool_calls_arguments_blank_to_empty_object",
  lambda do |tool_calls|
    Array(tool_calls).each do |tc|
      next unless tc.is_a?(Hash)

      fn = tc.fetch(:function, nil)
      next unless fn.is_a?(Hash)

      args = fn.fetch(:arguments, nil)
      next unless args.is_a?(String)
      next unless args.strip.empty?

      fn[:arguments] = "{}"
    end
  end,
)
