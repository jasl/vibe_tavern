# frozen_string_literal: true

require_relative "base"

module TavernKit
  class PromptBuilder
    module Dialects
      # OpenAI ChatCompletions dialect.
      #
      # Output is an Array<Hash> in the OpenAI message shape:
      #   { role: "system"|"user"|"assistant"|"tool", content: "...", ... }
      #
      # Tool calling passthrough (contract):
      # - assistant messages may include `tool_calls` (from Message.metadata[:tool_calls])
      # - tool result messages may include `tool_call_id` (from Message.metadata[:tool_call_id])
      # - optional `signature` passthrough
      class OpenAI < Base
        def convert(messages, **_opts)
          Array(messages).map { |m| convert_message(m) }
        end

        private

        def convert_message(message)
          tool_calls = fetch_meta(message, :tool_calls)
          tool_call_id = fetch_meta(message, :tool_call_id)
          signature = fetch_meta(message, :signature)

          h = {
            role: role_string(message.role),
            content: message.content,
          }
          h[:name] = message.name if message.name && !message.name.empty?
          h[:tool_calls] = tool_calls if tool_calls
          h[:tool_call_id] = tool_call_id if tool_call_id
          h[:signature] = signature if signature
          h
        end
      end
    end
  end
end

TavernKit::PromptBuilder::Dialects.register(:openai, TavernKit::PromptBuilder::Dialects::OpenAI)
