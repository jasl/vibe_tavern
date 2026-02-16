# frozen_string_literal: true

module AgentCore
  module PromptRunner
    # Shared helpers for tool execution.
    #
    # Used by Runner and ToolExecutor implementations to:
    # - size-limit tool results
    # - build safe summaries for traces/observability
    module ToolExecutionUtils
      module_function

      def summarize_tool_arguments(arguments, mode: :safe)
        case normalize_summary_mode(mode)
        when :debug
          json = safe_generate_json(arguments)
          AgentCore::Utils.truncate_utf8_bytes(json, max_bytes: 2_000)
        else
          safe_summarize_tool_arguments(arguments)
        end
      end

      def summarize_tool_result(result, mode: :safe)
        if normalize_summary_mode(mode) == :debug
          return debug_summarize_tool_result(result)
        end

        safe_summarize_tool_result(result)
      end

      def safe_summarize_tool_arguments(arguments)
        summary =
          case arguments
          when Hash
            keys =
              arguments.keys
                .map { |k| k.to_s }
                .uniq
                .sort

            preview = keys.first(50)
            suffix = preview.any? ? " keys=#{preview.join(",")}" : ""
            "type=Hash keys_count=#{keys.size}#{suffix}"
          when Array
            "type=Array size=#{arguments.size}"
          when nil
            "type=NilClass"
          else
            "type=#{arguments.class}"
          end

        AgentCore::Utils.truncate_utf8_bytes(summary, max_bytes: 2_000)
      rescue StandardError
        AgentCore::Utils.truncate_utf8_bytes("type=#{arguments.class}", max_bytes: 2_000)
      end
      private_class_method :safe_summarize_tool_arguments

      def safe_summarize_tool_result(result)
        unless result.is_a?(AgentCore::Resources::Tools::ToolResult)
          return safe_summarize_non_tool_result(result)
        end

        types =
          Array(result.content)
            .map { |b| b.is_a?(Hash) ? b[:type].to_s : nil }
            .compact
            .uniq
            .sort

        blocks_count = Array(result.content).size
        truncated = result.metadata.is_a?(Hash) && result.metadata[:truncated] == true
        text_bytes = result.text.to_s.bytesize

        summary = "types=#{types.join(",")} blocks=#{blocks_count} error=#{result.error?} text_bytes=#{text_bytes} truncated=#{truncated}"
        AgentCore::Utils.truncate_utf8_bytes(summary, max_bytes: 2_000)
      rescue StandardError
        safe_summarize_non_tool_result(result)
      end
      private_class_method :safe_summarize_tool_result

      def safe_summarize_non_tool_result(value)
        summary =
          case value
          when nil
            "type=NilClass"
          when String
            "type=String bytes=#{value.bytesize}"
          when Array
            "type=Array size=#{value.size}"
          when Hash
            "type=Hash size=#{value.size}"
          else
            "type=#{value.class}"
          end

        AgentCore::Utils.truncate_utf8_bytes(summary, max_bytes: 2_000)
      rescue StandardError
        AgentCore::Utils.truncate_utf8_bytes("type=#{value.class}", max_bytes: 2_000)
      end
      private_class_method :safe_summarize_non_tool_result

      def debug_summarize_tool_result(result)
        unless result.is_a?(AgentCore::Resources::Tools::ToolResult)
          return AgentCore::Utils.truncate_utf8_bytes(result.to_s, max_bytes: 2_000)
        end

        if result.has_non_text_content?
          types =
            result.content
              .map { |b| b.is_a?(Hash) ? b[:type].to_s : nil }
              .compact
              .uniq
              .sort

          text = result.text.to_s
          text = AgentCore::Utils.truncate_utf8_bytes(text, max_bytes: 1_600) unless text.empty?
          suffix = text.empty? ? "" : " text=#{text.inspect}"
          "non_text_types=#{types.join(",")} error=#{result.error?}#{suffix}"
        else
          AgentCore::Utils.truncate_utf8_bytes(result.text.to_s, max_bytes: 2_000)
        end
      rescue StandardError
        AgentCore::Utils.truncate_utf8_bytes(result.to_s, max_bytes: 2_000)
      end
      private_class_method :debug_summarize_tool_result

      def normalize_summary_mode(value)
        token = value.to_s.strip.downcase.tr("-", "_")
        return :debug if token == "debug"

        :safe
      rescue StandardError
        :safe
      end
      private_class_method :normalize_summary_mode

      def limit_tool_result(result, max_bytes:, tool_name:)
        return result unless result.is_a?(AgentCore::Resources::Tools::ToolResult)

        estimated_bytes = estimate_tool_result_bytes(result)
        return result unless estimated_bytes.is_a?(Integer)
        return result if estimated_bytes <= max_bytes

        marker = "\n\n[truncated]"
        text = result.text.to_s

        replacement_text =
          if text.strip.empty?
            "Tool '#{tool_name}' output omitted because it exceeded the size limit (max_bytes=#{max_bytes})."
          elsif max_bytes <= marker.bytesize
            AgentCore::Utils.truncate_utf8_bytes(marker, max_bytes: max_bytes)
          else
            AgentCore::Utils.truncate_utf8_bytes(text, max_bytes: max_bytes - marker.bytesize) + marker
          end

        AgentCore::Resources::Tools::ToolResult.new(
          content: [{ type: :text, text: replacement_text }],
          error: result.error?,
          metadata: result.metadata.merge(truncated: true, estimated_bytes: estimated_bytes, max_bytes: max_bytes)
        )
      rescue StandardError
        result
      end

      def estimate_tool_result_bytes(result)
        require "json"
        JSON.generate({ content: result.content, error: result.error? }).bytesize
      rescue StandardError
        result.text.to_s.bytesize
      end

      def safe_generate_json(value)
        require "json"
        JSON.generate(value)
      rescue StandardError
        value.to_s
      end
    end
  end
end
