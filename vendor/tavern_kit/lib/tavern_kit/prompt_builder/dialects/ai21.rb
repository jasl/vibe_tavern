# frozen_string_literal: true

require_relative "base"

module TavernKit
  class PromptBuilder
    module Dialects
      # AI21 chat dialect (best-effort generic role/content list).
      #
      # Output is an Array<Hash>:
      #   [{ role: "system"|"user"|"assistant", content: "..." }, ...]
      class AI21 < Base
        def convert(messages, **_opts)
          Array(messages).map do |msg|
            { role: role_string(msg.role), content: msg.content.to_s }
          end
        end
      end
    end
  end
end

TavernKit::PromptBuilder::Dialects.register(:ai21, TavernKit::PromptBuilder::Dialects::AI21)
