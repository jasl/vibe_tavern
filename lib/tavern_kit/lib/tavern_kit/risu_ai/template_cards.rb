# frozen_string_literal: true

module TavernKit
  module RisuAI
    # Prompt template assembly for RisuAI (Wave 5d).
    #
    # Characterization source:
    # - resources/Risuai/src/ts/process/index.svelte.ts (promptTemplate + positionParser)
    # - resources/Risuai/src/ts/process/prompt.ts (PromptItem types + stChatConvert)
    module TemplateCards
      POSITION_PLACEHOLDER = /\{\{position::(.+?)\}\}/.freeze
    end
  end
end

require_relative "template_cards/st_chat_convert"
require_relative "template_cards/assembler"
