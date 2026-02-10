# frozen_string_literal: true

require_relative "base"

module TavernKit
  class PromptBuilder
    module Dialects
      # Cohere Chat dialect.
      #
      # Output is a Hash:
      #   { chat_history: [{ role: "USER"|"CHATBOT", message: "..." }, ...] }
      class Cohere < Base
        def convert(messages, **_opts)
          history =
            Array(messages).map do |msg|
              role =
                case msg.role
                when :assistant then "CHATBOT"
                else "USER"
                end

              { role: role, message: msg.content.to_s }
            end

          { chat_history: history }
        end
      end
    end
  end
end

TavernKit::PromptBuilder::Dialects.register(:cohere, TavernKit::PromptBuilder::Dialects::Cohere)
