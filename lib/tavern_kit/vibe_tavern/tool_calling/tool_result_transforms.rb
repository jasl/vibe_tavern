# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolCalling
      # Provider/model compatibility shims applied to tool result envelopes,
      # after tool execution and before serialization into a tool message.
      #
      # The runner expects tool results to be JSON-serializable Hashes with
      # string keys, typically shaped like:
      #   { "ok" => true|false, "tool_name" => "...", "data" => {...}, "warnings" => [...], "errors" => [...] }
      #
      # Runtime stores only transform *names* so it stays serializable and can
      # be merged via presets. Upper layers can register additional transforms
      # if needed.
      module ToolResultTransforms
        REGISTRY = {}

        module_function

        def register(name, callable = nil, &block)
          transform = callable || block
          raise ArgumentError, "transform must respond to #call" unless transform&.respond_to?(:call)

          canonical = canonical_name(name)
          raise ArgumentError, "transform name is required" if canonical.empty?

          REGISTRY[canonical] = transform
        end

        # Applies named transforms to a tool result envelope.
        #
        # Transforms may:
        # - mutate the current envelope in place and return nil
        # - return a replacement Hash
        #
        # Any returned Hash is normalized to string keys.
        def apply(result, transforms, tool_name:, tool_call_id:, strict: false)
          current = deep_stringify_keys(result.is_a?(Hash) ? result : {})
          context = { tool_name: tool_name.to_s, tool_call_id: tool_call_id.to_s }

          Array(transforms).each do |name|
            canonical = canonical_name(name)
            next if canonical.empty?

            transform = REGISTRY[canonical]
            if transform
              returned =
                case transform.arity
                when 0
                  transform.call
                when 1
                  transform.call(current)
                else
                  transform.call(current, context)
                end

              case returned
              when nil
                current = deep_stringify_keys(current)
              when Hash
                current = deep_stringify_keys(returned)
              else
                raise ArgumentError, "Tool result transform must return a Hash or nil: #{name}" if strict
              end
            elsif strict
              raise ArgumentError, "Unknown tool result transform: #{name}"
            end
          end

          current
        end

        def canonical_name(name)
          name.to_s.strip.downcase.tr("-", "_")
        end
        private_class_method :canonical_name

        def deep_stringify_keys(value)
          case value
          when Hash
            value.each_with_object({}) do |(k, v), out|
              out[k.to_s] = deep_stringify_keys(v)
            end
          when Array
            value.map { |v| deep_stringify_keys(v) }
          else
            value
          end
        end
        private_class_method :deep_stringify_keys
      end
    end
  end
end

TavernKit::VibeTavern::ToolCalling::ToolResultTransforms.register(
  "tool_result_compact_envelope",
  lambda do |result|
    next unless result.is_a?(Hash)

    warnings = result.fetch("warnings", nil)
    result.delete("warnings") if warnings.is_a?(Array) && warnings.empty?

    errors = result.fetch("errors", nil)
    result.delete("errors") if errors.is_a?(Array) && errors.empty?

    data = result.fetch("data", nil)
    result.delete("data") if data.is_a?(Hash) && data.empty?
  end,
)
