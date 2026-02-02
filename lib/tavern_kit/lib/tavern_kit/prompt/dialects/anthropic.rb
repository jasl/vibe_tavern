# frozen_string_literal: true

require_relative "base"

module TavernKit
  module Dialects
    # Anthropic Messages dialect.
    #
    # Output is a Hash:
    #   { system: "....", messages: [{ role: "user"|"assistant", content: [...] }, ...] }
    #
    # Tool calling passthrough (Wave 4 contract):
    # - assistant messages with metadata[:tool_calls] -> tool_use blocks
    # - tool messages with metadata[:tool_call_id] -> tool_result blocks
    class Anthropic < Base
      def convert(messages, **_opts)
        messages = Array(messages)

        system_parts = []
        out_messages = []

        messages.each do |msg|
          case msg.role
          when :system
            system_parts << msg.content
          when :tool
            out_messages << tool_result_message(msg)
          when :user
            out_messages << { role: "user", content: [text_block(msg.content)] }
          when :assistant
            out_messages << assistant_message(msg)
          else
            # Best-effort fallback: keep role semantics but map to user/assistant.
            out_messages << { role: "user", content: [text_block(msg.content)] }
          end
        end

        { system: join_system(system_parts), messages: out_messages }
      end

      private

      def join_system(parts)
        parts = Array(parts).map(&:to_s).reject(&:empty?)
        return "" if parts.empty?

        parts.join("\n\n")
      end

      def text_block(text)
        { type: "text", text: text.to_s }
      end

      def assistant_message(message)
        tool_calls = fetch_meta(message, :tool_calls)
        blocks = []
        blocks << text_block(message.content) if !message.content.to_s.empty?

        if tool_calls.is_a?(Array)
          tool_calls.each do |call|
            blocks << tool_use_block(call)
          end
        end

        { role: "assistant", content: blocks }
      end

      def tool_use_block(call)
        # Tool call payloads can be app-provided, so accept mixed-key hashes but
        # normalize access via HashAccessor to avoid ad-hoc key fallback logic.
        h = TavernKit::Utils::HashAccessor.wrap(call)
        id = h[:id]

        fn = h.fetch(:function, default: {})
        fn_h = TavernKit::Utils::HashAccessor.wrap(fn)
        name = fn_h[:name]
        args = fn_h[:arguments]

        {
          type: "tool_use",
          id: id.to_s,
          name: name.to_s,
          input: safe_parse_json(args) || {},
        }
      end

      def tool_result_message(message)
        tool_call_id = fetch_meta(message, :tool_call_id)

        {
          role: "user",
          content: [
            {
              type: "tool_result",
              tool_use_id: tool_call_id.to_s,
              content: message.content.to_s,
            },
          ],
        }
      end
    end
  end
end

TavernKit::Dialects.register(:anthropic, TavernKit::Dialects::Anthropic)
