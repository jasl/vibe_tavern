# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module Preflight
      module_function

      def validate_request!(capabilities:, stream:, tools:, response_format:)
        unless capabilities.is_a?(TavernKit::VibeTavern::Capabilities)
          raise ArgumentError, "capabilities must be a TavernKit::VibeTavern::Capabilities"
        end

        response_format_kind = classify_response_format(response_format)
        has_response_format = !response_format_kind.nil?

        if tools && has_response_format
          raise ArgumentError, "tools and response_format cannot be used in the same request"
        end

        if stream == true && (tools || has_response_format)
          raise ArgumentError, "streaming does not support tool calling or response_format"
        end

        if tools && !capabilities.supports_tool_calling
          raise ArgumentError, "provider/model does not support tools"
        end

        if stream == true && !capabilities.supports_streaming
          raise ArgumentError, "provider/model does not support streaming"
        end

        case response_format_kind
        when :json_object
          unless capabilities.supports_response_format_json_object
            raise ArgumentError, "provider/model does not support response_format: json_object"
          end
        when :json_schema
          unless capabilities.supports_response_format_json_schema
            raise ArgumentError, "provider/model does not support response_format: json_schema"
          end
        when :other
          unless capabilities.supports_response_format_json_object || capabilities.supports_response_format_json_schema
            raise ArgumentError, "provider/model does not support response_format"
          end
        end
      end

      def classify_response_format(value)
        return nil if value.nil? || value == false
        return :other unless value.is_a?(Hash)

        value.each_key do |key|
          raise ArgumentError, "response_format keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
        end

        type = value.fetch(:type, nil).to_s.strip
        return :other if type.empty?
        return :json_object if type == "json_object"
        return :json_schema if type == "json_schema"

        :other
      end
      private_class_method :classify_response_format
    end
  end
end
