# frozen_string_literal: true

require_relative "base"

module TavernKit
  module Dialects
    # Google (Gemini) dialect.
    #
    # Output is a Hash:
    #   { system_instruction: { parts: [...] }, contents: [...] }
    class Google < Base
      def convert(messages, **_opts)
        messages = Array(messages)

        system_parts = []
        contents = []

        messages.each do |msg|
          case msg.role
          when :system
            system_parts << { text: msg.content.to_s }
          when :assistant
            contents << { role: "model", parts: [{ text: msg.content.to_s }] }
          else
            contents << { role: "user", parts: [{ text: msg.content.to_s }] }
          end
        end

        system_instruction =
          if system_parts.any?
            { parts: system_parts }
          else
            nil
          end

        compact_hash(system_instruction: system_instruction, contents: contents)
      end
    end
  end
end

TavernKit::Dialects.register(:google, TavernKit::Dialects::Google)
