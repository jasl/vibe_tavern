# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolCalling
      class ToolDispatcher
        DEFAULT_TOOL_NAME_ALIASES = {}.freeze

        def initialize(executor:, registry:, expose: :model, tool_name_aliases: nil)
          @executor = executor
          @registry = registry
          @expose = expose
          @tool_name_aliases = tool_name_aliases || DEFAULT_TOOL_NAME_ALIASES
        end

        def execute(name:, args:)
          name = normalize_tool_name(name.to_s.strip)
          args = args.is_a?(Hash) ? args : {}

          unless @registry.include?(name, expose: @expose)
            return error_envelope(name, code: "TOOL_NOT_ALLOWED", message: "Tool not allowed: #{name}")
          end

          result = @executor.call(name: name, args: args)

          # Allow executors to return already-normalized envelopes, but don't
          # require it for simple implementations.
          if result.is_a?(Hash) && (result.key?("ok") || result.key?(:ok))
            return stringify_keys(result)
          end

          ok_envelope(name, result)
        rescue ArgumentError => e
          error_envelope(name, code: "ARGUMENT_ERROR", message: e.message)
        rescue StandardError => e
          # Unexpected programming error: surface clearly so tests/debugging can catch it.
          error_envelope(name, code: "INTERNAL_ERROR", message: "#{e.class}: #{e.message}")
        end

        private

        def ok_envelope(name, data)
          {
            "ok" => true,
            "tool_name" => name,
            "data" => data.is_a?(Hash) ? data : { "value" => data },
            "warnings" => [],
            "errors" => [],
          }
        end

        def error_envelope(name, code:, message:)
          {
            "ok" => false,
            "tool_name" => name,
            "data" => {},
            "warnings" => [],
            "errors" => [
              {
                "code" => code,
                "message" => message.to_s,
              },
            ],
          }
        end

        def normalize_tool_name(name)
          normalized = @tool_name_aliases.fetch(name, name)

          # Some providers/models may output `foo.bar` even if we recommend `_`.
          # If the dotted name is not registered but the underscored variant is,
          # accept it for robustness.
          if normalized.include?(".")
            underscored = normalized.tr(".", "_")
            return underscored if @registry.include?(underscored, expose: @expose)
          end

          normalized
        end

        def stringify_keys(hash)
          hash.each_with_object({}) do |(k, v), out|
            out[k.to_s] =
              case v
              when Hash
                stringify_keys(v)
              when Array
                v.map { |vv| vv.is_a?(Hash) ? stringify_keys(vv) : vv }
              else
                v
              end
          end
        end
      end
    end
  end
end
