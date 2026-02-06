# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolCalling
      # Provider/model compatibility shims applied to tool result envelopes,
      # after tool execution and before serialization into a tool message.
      #
      # The runner expects tool results to be JSON-serializable Hashes with
      # symbol keys, typically shaped like:
      #   { ok: true|false, tool_name: "...", data: {...}, warnings: [...], errors: [...] }
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
        # Any returned Hash is normalized to symbol keys.
        def apply(result, transforms, tool_name:, tool_call_id:, strict: false)
          current = normalize_result_hash(result)
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
                current = normalize_result_hash(current)
              when Hash
                current = normalize_result_hash(returned)
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

        def normalize_result_hash(value)
          raw = value.is_a?(Hash) ? value : {}

          normalized =
            raw.each_with_object({}) do |(k, v), out|
              key = k.is_a?(Symbol) ? k : k.to_s.to_sym
              out[key] = v
            end

          warnings = normalized.fetch(:warnings, nil)
          if warnings.is_a?(Array)
            normalized[:warnings] = warnings.map { |w| w.is_a?(Hash) ? symbolize_hash_keys(w) : w }
          end

          errors = normalized.fetch(:errors, nil)
          if errors.is_a?(Array)
            normalized[:errors] = errors.map { |e| e.is_a?(Hash) ? symbolize_hash_keys(e) : e }
          end

          tool_name = normalized.fetch(:tool_name, nil)
          tool_name = tool_name.to_s.strip
          if tool_name.empty?
            normalized.delete(:tool_name)
          else
            normalized[:tool_name] = tool_name
          end

          normalized
        end
        private_class_method :normalize_result_hash

        def symbolize_hash_keys(hash)
          hash.each_with_object({}) do |(k, v), out|
            key = k.is_a?(Symbol) ? k : k.to_s.to_sym
            out[key] = v
          end
        end
        private_class_method :symbolize_hash_keys
      end
    end
  end
end

TavernKit::VibeTavern::ToolCalling::ToolResultTransforms.register(
  "tool_result_compact_envelope",
  lambda do |result|
    next unless result.is_a?(Hash)

    warnings = result.fetch(:warnings, nil)
    result.delete(:warnings) if warnings.is_a?(Array) && warnings.empty?

    errors = result.fetch(:errors, nil)
    result.delete(:errors) if errors.is_a?(Array) && errors.empty?

    data = result.fetch(:data, nil)
    result.delete(:data) if data.is_a?(Hash) && data.empty?
  end,
)
