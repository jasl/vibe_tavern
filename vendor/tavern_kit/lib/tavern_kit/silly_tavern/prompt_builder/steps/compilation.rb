# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module PromptBuilder
      module Steps
        # Compile pinned groups + prompt entries into a single block list.
        module Compilation
          extend TavernKit::PromptBuilder::Step

          Config =
            Data.define do
              def self.from_hash(raw)
                return raw if raw.is_a?(self)

                raise ArgumentError, "compilation step config must be a Hash" unless raw.is_a?(Hash)
                raw.each_key do |key|
                  raise ArgumentError, "compilation step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
                end

                if raw.any?
                  raise ArgumentError, "compilation step does not accept step config keys: #{raw.keys.inspect}"
                end

                new
              end
            end

          def self.before(ctx, _config)
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
            ctx.instrument(:stat, step: ctx.current_step, key: :blocks, value: blocks.size)
          end
        end
      end
    end
  end
end
