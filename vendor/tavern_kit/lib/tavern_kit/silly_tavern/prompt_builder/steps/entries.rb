# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module PromptBuilder
      module Steps
      # Prompt entry filtering + ST normalization rules.
      class Entries < TavernKit::PromptBuilder::Step
        Config =
          Data.define do
            def self.from_hash(raw)
              return raw if raw.is_a?(self)

              raise ArgumentError, "entries step config must be a Hash" unless raw.is_a?(Hash)
              raw.each_key do |key|
                raise ArgumentError, "entries step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
              end

              if raw.any?
                raise ArgumentError, "entries step does not accept step config keys: #{raw.keys.inspect}"
              end

              new
            end
          end

        FORCE_RELATIVE_IDS = %w[
          chat_history
          chat_examples
        ].freeze

        FORCE_LAST_IDS = %w[
          post_history_instructions
        ].freeze

        def self.before(ctx, _config)
          ctx.chat_scan_messages ||= build_chat_scan_messages(ctx)
          ctx.default_chat_depth ||= default_chat_depth(ctx)

          cond_ctx = {
            chat_scan_messages: ctx.chat_scan_messages,
            default_chat_depth: ctx.default_chat_depth,
            turn_count: ctx.turn_count,
            character: ctx.character,
            user: ctx.user,
          }

          list = ctx.preset.effective_prompt_entries

          filtered = list.filter_map do |entry|
            next nil unless entry.enabled?
            next nil unless entry.triggered_by?(ctx.generation_type)
            next nil unless entry.active_for?(cond_ctx)

            normalize_entry(entry)
          end

          # ST normalization: some ids are pinned to the end of the prompt order.
          forced_last, rest = filtered.partition { |e| FORCE_LAST_IDS.include?(e.id) }
          ctx.prompt_entries = (rest + forced_last)

          ctx.instrument(:stat, step: ctx.current_step, key: :prompt_entries, value: ctx.prompt_entries.size)
        end

        class << self
          private

        def build_chat_scan_messages(ctx)
          history = TavernKit::ChatHistory.wrap(ctx.history)

          messages = []
          user_text = ctx.user_message.to_s.strip
          messages << user_text unless user_text.empty?

          history.last(1_000).reverse_each do |m|
            s = m.content.to_s.strip
            next if s.empty?

            messages << s
          end

          messages
        rescue ArgumentError
          user_text = ctx.user_message.to_s.strip
          user_text.empty? ? [] : [user_text]
        end

        def default_chat_depth(ctx)
          depth = ctx.preset.world_info_depth.to_i
          depth.positive? ? depth : 2
        end

        def normalize_entry(entry)
          if FORCE_RELATIVE_IDS.include?(entry.id) && entry.in_chat?
            entry = copy_entry(entry, position: :relative)
          end

          if FORCE_LAST_IDS.include?(entry.id) && entry.in_chat?
            entry = copy_entry(entry, position: :relative)
          end

          entry
        end

        def copy_entry(entry, **overrides)
          attrs = entry.to_h.merge(overrides)
          TavernKit::PromptBuilder::PromptEntry.new(**attrs)
        end
        end
      end
      end
    end
  end
end
