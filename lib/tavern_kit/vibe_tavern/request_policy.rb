# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module RequestPolicy
      module_function

      def normalize_options!(options, capabilities:)
        raise ArgumentError, "options must be a Hash" unless options.is_a?(Hash)
        unless capabilities.nil? || capabilities.respond_to?(:supports_parallel_tool_calls)
          raise ArgumentError, "capabilities must respond to supports_parallel_tool_calls"
        end

        response_format = options.fetch(:response_format, nil)
        structured = !(response_format.nil? || response_format == false)

        tool_calling = options.key?(:tools) || options.key?(:tool_choice)

        if structured
          options[:parallel_tool_calls] = false
        elsif tool_calling && !options.key?(:parallel_tool_calls)
          options[:parallel_tool_calls] = false
        end

        if options.key?(:parallel_tool_calls)
          value = options.fetch(:parallel_tool_calls)
          unless value == true || value == false
            raise ArgumentError, "parallel_tool_calls must be a boolean"
          end
        end

        options
      end

      def filter_request!(request, capabilities:)
        raise ArgumentError, "request must be a Hash" unless request.is_a?(Hash)

        return request unless request.key?(:parallel_tool_calls)

        supports_parallel_tool_calls =
          capabilities.respond_to?(:supports_parallel_tool_calls) && capabilities.supports_parallel_tool_calls == true

        request.delete(:parallel_tool_calls) unless supports_parallel_tool_calls

        request
      end
    end
  end
end
