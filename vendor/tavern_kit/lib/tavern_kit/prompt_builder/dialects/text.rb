# frozen_string_literal: true

require_relative "base"

module TavernKit
  class PromptBuilder
    module Dialects
      # Text-completion dialect.
      #
      # Output is a Hash:
      #   { prompt: "...", stop_sequences: [...] }
      class Text < Base
        def convert(messages, stop_sequences: nil, **_opts)
          prompt = Array(messages).map { |m| m.content.to_s }.reject(&:empty?).join("\n")
          { prompt: prompt, stop_sequences: Array(stop_sequences).compact.map(&:to_s) }
        end
      end
    end
  end
end

TavernKit::PromptBuilder::Dialects.register(:text, TavernKit::PromptBuilder::Dialects::Text)
