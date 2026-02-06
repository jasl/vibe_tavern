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
          if result.is_a?(Hash)
            normalized = deep_symbolize_keys(result)
            return normalize_envelope(name, normalized) if normalized.key?(:ok)
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
          data = deep_symbolize_keys(data) if data.is_a?(Hash)

          {
            ok: true,
            tool_name: name,
            data: data.is_a?(Hash) ? data : { value: data },
            warnings: [],
            errors: [],
          }
        end

        def error_envelope(name, code:, message:)
          {
            ok: false,
            tool_name: name,
            data: {},
            warnings: [],
            errors: [
              {
                code: code,
                message: message.to_s,
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

        def normalize_envelope(default_tool_name, value)
          raw = value.is_a?(Hash) ? value : {}

          ok = raw.fetch(:ok, false)
          tool_name = raw.fetch(:tool_name, nil)
          data = raw.fetch(:data, nil)
          warnings = raw.fetch(:warnings, nil)
          errors = raw.fetch(:errors, nil)

          {
            ok: ok == true,
            tool_name: tool_name.to_s.strip.empty? ? default_tool_name.to_s : tool_name.to_s,
            data: data.is_a?(Hash) ? data : (data.nil? ? {} : { value: data }),
            warnings: warnings.is_a?(Array) ? warnings : [],
            errors: normalize_errors(errors),
          }
        end

        def normalize_errors(errors)
          Array(errors).filter_map do |e|
            next unless e.is_a?(Hash)

            code = e.fetch(:code, nil)
            message = e.fetch(:message, nil)

            { code: code.to_s, message: message.to_s }
          end
        end

        def deep_symbolize_keys(value)
          case value
          when Hash
            value.each_with_object({}) do |(k, v), out|
              out[k.to_s.to_sym] = deep_symbolize_keys(v)
            end
          when Array
            value.map { |v| deep_symbolize_keys(v) }
          else
            value
          end
        end
      end
    end
  end
end
