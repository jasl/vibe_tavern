# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Lore
      # RisuAI-specific lore scan input.
      #
      # Mirrors high-level knobs used by `loadLoreBookV3Prompt()`:
      # resources/Risuai/src/ts/process/lorebook.svelte.ts
      class ScanInput < TavernKit::Lore::ScanInput
        attr_reader :scan_depth, :recursive_scanning, :full_word_matching, :chat_length, :greeting_index, :variables, :rng

        def initialize(
          messages:,
          books:,
          budget:,
          scan_depth: 50,
          recursive_scanning: true,
          full_word_matching: false,
          chat_length: nil,
          greeting_index: nil,
          variables: nil,
          rng: nil
        )
          super(messages: messages, books: books, budget: budget)

          @scan_depth = Integer(scan_depth)
          @recursive_scanning = recursive_scanning == true
          @full_word_matching = full_word_matching == true

          @chat_length =
            if chat_length.nil?
              # Upstream uses `currentChat.length + 1` ("includes first message").
              Array(messages).length + 1
            else
              Integer(chat_length)
            end

          @greeting_index = greeting_index.nil? ? nil : Integer(greeting_index)
          @variables = variables
          @rng = rng
        end

        def recursive_scanning? = @recursive_scanning
        def full_word_matching? = @full_word_matching
      end
    end
  end
end
