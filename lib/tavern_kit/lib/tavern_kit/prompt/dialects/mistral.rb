# frozen_string_literal: true

require_relative "base"

module TavernKit
  module Dialects
    # Mistral chat dialect (OpenAI-like role/content list).
    #
    # Output is an Array<Hash>:
    #   [{ role: "system"|"user"|"assistant", content: "..." }, ...]
    class Mistral < Base
      def convert(messages, use_prefix: false, **_opts)
        msgs = Array(messages).map { |m| { role: role_string(m.role), content: m.content.to_s } }
        return msgs unless use_prefix

        # Optional compatibility: prefix role labels into content (for legacy models).
        msgs.map do |m|
          prefix = m[:role].upcase
          m.merge(content: "#{prefix}: #{m[:content]}")
        end
      end
    end
  end
end

TavernKit::Dialects.register(:mistral, TavernKit::Dialects::Mistral)
