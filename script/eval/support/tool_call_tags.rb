# frozen_string_literal: true

require "json"

require_relative "verbatim_masker"

module VibeTavernEval
  module ToolCallTags
    module_function

    # Extract OpenAI-style tool_calls from textual <tool_call>...</tool_call>
    # tags, returning cleaned content and parsed tool_calls.
    #
    # @param content [String]
    # @param escape_hatch [Hash, nil] passed to VerbatimMasker
    # @return [Hash] { content: String, tool_calls: Array<Hash> }
    def extract(content, escape_hatch: nil)
      return { content: content.to_s, tool_calls: [] } unless content.is_a?(String)
      return { content: content, tool_calls: [] } unless content.include?("<tool_call>")

      masked, placeholders =
        VibeTavernEval::VerbatimMasker.mask(
          content,
          escape_hatch: escape_hatch,
        )

      tagged = masked.scan(/<tool_call>(.*?)<\/tool_call>/m).flatten
      if tagged.empty?
        return { content: VibeTavernEval::VerbatimMasker.unmask(masked, placeholders), tool_calls: [] }
      end

      tool_calls =
        tagged.each_with_index.filter_map do |payload, idx|
          extract_tool_call(payload, idx + 1)
        end

      if tool_calls.empty?
        return { content: VibeTavernEval::VerbatimMasker.unmask(masked, placeholders), tool_calls: [] }
      end

      cleaned_masked = masked.gsub(/<tool_call>.*?<\/tool_call>/m, "").strip

      {
        content: VibeTavernEval::VerbatimMasker.unmask(cleaned_masked, placeholders),
        tool_calls: tool_calls,
      }
    rescue StandardError
      { content: content.to_s, tool_calls: [] }
    end

    def extract_tool_call(payload, index)
      raw = payload.to_s.strip
      return nil if raw.empty?

      name = nil
      args = nil

      begin
        parsed = JSON.parse(raw)
        if parsed.is_a?(Hash)
          if parsed["function"].is_a?(Hash)
            fn = parsed["function"]
            name = fn["name"].to_s.strip
            args = fn.key?("arguments") ? fn["arguments"] : nil
          else
            name = parsed["name"].to_s.strip
            args = parsed.key?("arguments") ? parsed["arguments"] : parsed["args"]
          end
        end
      rescue JSON::ParserError
        if (m = raw.match(/\A([a-zA-Z0-9_.-]+)\s+(\{.*\})\z/m))
          name = m.fetch(1).to_s.strip
          args = m.fetch(2).to_s
        elsif raw.match?(/\A[a-zA-Z0-9_.-]+\z/)
          name = raw
        end
      end

      return nil if name.to_s.empty?

      arguments =
        case args
        when nil
          "{}"
        when String
          args
        when Hash, Array
          JSON.generate(args)
        else
          "{}"
        end

      {
        "id" => "tag_call_#{index}",
        "type" => "function",
        "function" => {
          "name" => name,
          "arguments" => arguments,
        },
      }
    end
    private_class_method :extract_tool_call
  end
end
