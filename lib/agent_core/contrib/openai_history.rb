# frozen_string_literal: true

module AgentCore
  module Contrib
    module OpenAIHistory
      module_function

      def coerce_messages(value)
        Array(value).map { |msg| coerce_message(msg) }
      end

      def coerce_message(value)
        return value if value.is_a?(AgentCore::Message)
        return coerce_hash_message(value) if value.is_a?(Hash)

        if value.respond_to?(:role) && value.respond_to?(:content)
          role = normalize_role(value.role)
          content = value.content.to_s
          name = value.respond_to?(:name) ? value.name : nil
          tool_call_id = value.respond_to?(:tool_call_id) ? value.tool_call_id : nil
          metadata = value.respond_to?(:metadata) ? value.metadata : nil

          tool_calls = value.respond_to?(:tool_calls) ? value.tool_calls : nil
          tool_calls = coerce_tool_calls(tool_calls) if tool_calls

          return AgentCore::Message.new(
            role: role,
            content: content,
            tool_calls: tool_calls,
            tool_call_id: tool_call_id,
            name: name,
            metadata: metadata,
          )
        end

        raise ArgumentError, "history messages must be AgentCore::Message or Hash-like with role/content"
      end

      def coerce_hash_message(hash)
        h = AgentCore::Utils.symbolize_keys(hash)

        role = normalize_role(h.fetch(:role, nil))
        content = h.fetch(:content, nil).to_s
        name = h.fetch(:name, nil)
        tool_call_id = h.fetch(:tool_call_id, nil)
        metadata = h.fetch(:metadata, nil)

        tool_calls = h.fetch(:tool_calls, nil)
        tool_calls = coerce_tool_calls(tool_calls) if tool_calls

        AgentCore::Message.new(
          role: role,
          content: content,
          tool_calls: tool_calls,
          tool_call_id: tool_call_id,
          name: name,
          metadata: metadata,
        )
      end
      private_class_method :coerce_hash_message

      def coerce_tool_calls(value)
        calls = Array(value).map.with_index(1) do |raw, idx|
          coerce_tool_call(raw, fallback_id: "tc_#{idx}")
        end

        calls.empty? ? nil : calls
      end
      private_class_method :coerce_tool_calls

      def coerce_tool_call(value, fallback_id:)
        return value if value.is_a?(AgentCore::ToolCall)

        raise ArgumentError, "tool_calls entries must be Hash-like" unless value.is_a?(Hash)

        h = AgentCore::Utils.symbolize_keys(value)

        if h.key?(:name) && h.key?(:arguments)
          return AgentCore::ToolCall.from_h(h)
        end

        fn = AgentCore::Utils.symbolize_keys(h.fetch(:function, nil))
        name = fn.fetch(:name, "").to_s.strip
        raise ArgumentError, "tool_call.function.name is required" if name.empty?

        args_hash, parse_error = AgentCore::Utils.parse_tool_arguments(fn.fetch(:arguments, nil))

        id = h.fetch(:id, nil).to_s.strip
        id = fallback_id if id.empty?

        AgentCore::ToolCall.new(
          id: id,
          name: name,
          arguments: args_hash,
          arguments_parse_error: parse_error,
        )
      end
      private_class_method :coerce_tool_call

      def normalize_role(value)
        str = value.to_s
        return :tool_result if str == "tool"

        sym = str.to_sym
        unless AgentCore::Message::ROLES.include?(sym)
          raise ArgumentError, "Invalid message role: #{value.inspect}"
        end

        sym
      end
      private_class_method :normalize_role
    end
  end
end
