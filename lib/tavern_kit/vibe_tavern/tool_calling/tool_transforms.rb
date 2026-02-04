# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolCalling
      # Provider/model compatibility shims applied to outbound OpenAI-style tools.
      #
      # Runtime stores only transform *names* so it stays serializable and can be
      # merged via presets. Upper layers can register additional transforms if
      # needed.
      module ToolTransforms
        REGISTRY = {}

        module_function

        def register(name, callable = nil, &block)
          transform = callable || block
          raise ArgumentError, "transform must respond to #call" unless transform&.respond_to?(:call)

          canonical = canonical_name(name)
          raise ArgumentError, "transform name is required" if canonical.empty?

          REGISTRY[canonical] = transform
        end

        # Applies named transforms to a tools array.
        #
        # Each transform receives a mutable Array of tool hashes and may mutate it
        # in place. If the transform returns an Array, the returned Array becomes
        # the new working set for subsequent transforms.
        def apply(tools, transforms, strict: false)
          current = Array(tools).map { |t| deep_symbolize_keys(t) }

          Array(transforms).each do |name|
            canonical = canonical_name(name)
            next if canonical.empty?

            transform = REGISTRY[canonical]
            if transform
              result = transform.call(current)
              current = result if result.is_a?(Array)
            elsif strict
              raise ArgumentError, "Unknown tool transform: #{name}"
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

TavernKit::VibeTavern::ToolCalling::ToolTransforms.register(
  "openai_tools_strip_function_descriptions",
  lambda do |tools|
    Array(tools).each do |tool|
      next unless tool.is_a?(Hash)

      next unless tool.fetch(:type, nil) == "function"

      fn = tool.fetch(:function, nil)
      next unless fn.is_a?(Hash)

      fn.delete(:description)
    end
  end,
)
