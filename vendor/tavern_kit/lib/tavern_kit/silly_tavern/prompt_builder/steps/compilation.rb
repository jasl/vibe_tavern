# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module PromptBuilder
      module Steps
      # Compile pinned groups + prompt entries into a single block list.
      class Compilation < TavernKit::PromptBuilder::Step
        private

        def before(ctx)
          blocks = []

          Array(ctx.prompt_entries).each do |entry|
            if entry.pinned?
              blocks.concat(Array(ctx.pinned_groups[entry.id]))
              next
            end

            # In-chat entries are converted to injections and applied in Step 5.
            next if entry.in_chat?

            content = entry.content.to_s
            next if content.strip.empty?

            blocks << TavernKit::PromptBuilder::Block.new(
              role: entry.role,
              content: content,
              slot: entry.id.to_sym,
              token_budget_group: :system,
              removable: false,
              metadata: {
                source: :prompt_entry,
                prompt_entry_id: entry.id,
                prompt_entry_name: entry.name,
              },
            )
          end

          ctx.blocks = blocks
          ctx.instrument(:stat, step: :compilation, key: :blocks, value: blocks.size)
        end
      end
      end
    end
  end
end
