# frozen_string_literal: true

require_relative "base"

module TavernKit
  module Dialects
    # Mistral chat dialect (OpenAI-like role/content list).
    #
    # Output is an Array<Hash>:
    #   [{ role: "system"|"user"|"assistant", content: "..." }, ...]
    class Mistral < Base
      def convert(messages, **_opts)
        Array(messages).map { |m| { role: role_string(m.role), content: m.content.to_s } }
      end
    end
  end
end

TavernKit::Dialects.register(:mistral, TavernKit::Dialects::Mistral)
