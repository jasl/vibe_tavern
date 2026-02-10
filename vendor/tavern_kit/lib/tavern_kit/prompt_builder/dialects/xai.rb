# frozen_string_literal: true

require_relative "base"

module TavernKit
  class PromptBuilder
    module Dialects
      # xAI chat dialect (OpenAI-like role/content list).
      class XAI < Base
        def convert(messages, **_opts)
          Array(messages).map { |m| { role: role_string(m.role), content: m.content.to_s } }
        end
      end
    end
  end
end

TavernKit::PromptBuilder::Dialects.register(:xai, TavernKit::PromptBuilder::Dialects::XAI)
