# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Middleware
      # Wave 4: ST injection stage (extension prompts + Author's Note + persona).
      class Injection < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          injections = collect_injections(ctx)

          # Apply story string (text dialect only). This may:
          # - consume before/after injections into anchorBefore/anchorAfter
          # - clear groups that would otherwise duplicate story-string content
          apply_story_string(ctx, injections)

          apply_before_after_injections(ctx, injections) unless text_dialect?(ctx)
          apply_in_chat_injections(ctx, injections)

          remove_ephemeral_injections(ctx, injections)
        end

        Injections = Struct.new(
          :before,         # Array<InjectionRegistry::Entry>
          :after,          # Array<InjectionRegistry::Entry>
          :chat,           # Array<InjectionRegistry::Entry>
          :ephemeral_ids,  # Array<String>
          keyword_init: true,
        )

        def collect_injections(ctx)
          before_entries = []
          after_entries = []
          chat_entries = []
          ephemeral_ids = []

          registry = ctx.injection_registry
          if registry
            registry.each do |entry|
              next unless entry.active_for?(ctx)

              content = entry.content.to_s.strip
              next if content.empty?

              case entry.position.to_sym
              when :before
                before_entries << entry
              when :after
                after_entries << entry
              when :chat
                chat_entries << entry
              end

              ephemeral_ids << entry.id if entry.ephemeral?
            end
          end

          # PromptManager-style in-chat prompt entries.
          Array(ctx.prompt_entries).each do |entry|
            next if entry.pinned?
            next unless entry.in_chat?

            content = entry.content.to_s.strip
            next if content.empty?

            chat_entries << TavernKit::InjectionRegistry::Entry.new(
              id: entry.id,
              content: content,
              position: :chat,
              depth: entry.depth,
              role: entry.role,
              scan: false,
              ephemeral: false,
              filter: nil,
            )
          end

          persona_text = ctx.user.respond_to?(:persona_text) ? ctx.user.persona_text.to_s : ""
          persona_position = ctx.fetch(:persona_position, :in_prompt)
          persona_depth = ctx.fetch(:persona_depth, 0)
          persona_role = ctx.fetch(:persona_role, :system)

          persona_at_depth = TavernKit::SillyTavern::InjectionPlanner.persona_at_depth_entry(
            text: persona_text,
            position: persona_position,
            depth: persona_depth,
            role: persona_role,
          )
          chat_entries << persona_at_depth if persona_at_depth

          authors_note = build_authors_note_entry(ctx, persona_text: persona_text, persona_position: persona_position)
          if authors_note
            case authors_note.position
            when :before then before_entries << authors_note
            when :after then after_entries << authors_note
            when :chat then chat_entries << authors_note
            end
          end

          # World Info at-depth entries are represented as in-chat injections.
          Array(ctx.lore_result&.activated_entries).each do |entry|
            next unless entry.position.to_s == "at_depth"

            ext = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry)

            chat_entries << TavernKit::InjectionRegistry::Entry.new(
              id: entry.id,
              content: entry.content.to_s,
              position: :chat,
              depth: ext.depth,
              role: ext.role,
              scan: false,
              ephemeral: false,
              filter: nil,
            )
          end

          Injections.new(
            before: before_entries,
            after: after_entries,
            chat: chat_entries,
            ephemeral_ids: ephemeral_ids,
          )
        end

        def build_authors_note_entry(ctx, persona_text:, persona_position:)
          # Allow Prompt Manager to disable authors_note if it exists as a pinned entry.
          has_slot = Array(ctx.prompt_entries).any? { |e| e.id == "authors_note" }
          return nil unless has_slot

          entry = TavernKit::SillyTavern::InjectionPlanner.authors_note_entry(
            turn_count: ctx.turn_count,
            text: ctx.preset.authors_note,
            frequency: ctx.preset.authors_note_frequency,
            position: ctx.preset.authors_note_position,
            depth: ctx.preset.authors_note_depth,
            role: ctx.preset.authors_note_role,
            allow_wi_scan: ctx.preset.authors_note_allow_wi_scan,
            overrides: ctx.authors_note_overrides,
            persona_text: persona_text,
            persona_position: persona_position,
          )
          return nil unless entry

          apply_world_info_to_authors_note(entry, ctx.lore_result)
        end

        def apply_world_info_to_authors_note(entry, lore_result)
          return entry unless entry

          top, bottom = world_info_an_entries(lore_result)
          return entry if top.empty? && bottom.empty?

          content = entry.content.to_s

          combined = +""
          combined << top.join("\n") unless top.empty?
          combined << "\n" unless combined.empty? || content.empty?
          combined << content
          combined << "\n" unless combined.empty? || bottom.empty?
          combined << bottom.join("\n") unless bottom.empty?

          combined = combined.gsub(/\A\n+|\n+\z/, "")

          entry.with(content: combined)
        end

        def world_info_an_entries(lore_result)
          entries = Array(lore_result&.activated_entries)
          top_entries = entries.select { |e| e.position.to_s == "top_of_an" }
          bottom_entries = entries.select { |e| e.position.to_s == "bottom_of_an" }

          build_list = lambda do |list|
            out = []
            list.sort_by { |e| [-e.insertion_order.to_i, e.id.to_s] }.each do |e|
              out.unshift(e.content.to_s)
            end
            out
          end

          [build_list.call(top_entries), build_list.call(bottom_entries)]
        end

        def apply_story_string(ctx, injections)
          return unless text_dialect?(ctx)

          preset = ctx.preset
          template = preset.effective_context_template
          instruct = preset.effective_instruct

          persona_position = ctx.fetch(:persona_position, :in_prompt).to_s.strip.downcase.to_sym
          persona_text = ctx.user.respond_to?(:persona_text) ? ctx.user.persona_text.to_s : ""
          persona_value = persona_position == :in_prompt ? persona_text : ""

          char = ctx.character
          data = char.data

          world_info_before = join_world_info(ctx.lore_result, position: "before_char_defs")
          world_info_after = join_world_info(ctx.lore_result, position: "after_char_defs")

          anchors = story_string_anchors(injections)

          examples_raw = data.mes_example.to_s
          examples_blocks = TavernKit::SillyTavern::ExamplesParser.parse(examples_raw)

          params = {
            "description" => data.description.to_s,
            "personality" => data.personality.to_s,
            "persona" => persona_value.to_s,
            "scenario" => data.scenario.to_s,
            "system" => ctx.pinned_groups.fetch("main_prompt", []).first&.content.to_s,
            "char" => char.name.to_s,
            "user" => ctx.user.name.to_s,
            "wiBefore" => world_info_before,
            "wiAfter" => world_info_after,
            "loreBefore" => world_info_before,
            "loreAfter" => world_info_after,
            "anchorBefore" => anchors.fetch(:before),
            "anchorAfter" => anchors.fetch(:after),
            "mesExamples" => examples_blocks.join,
            "mesExamplesRaw" => examples_blocks.join,
          }

          story_string = template.render(params)

          combined =
            if instruct.enabled? && template.story_string_position != TavernKit::SillyTavern::ContextTemplate::Position::IN_CHAT
              "#{instruct.story_string_prefix}#{story_string}#{instruct.story_string_suffix}"
            else
              story_string
            end

          if template.story_string_position == TavernKit::SillyTavern::ContextTemplate::Position::IN_CHAT
            injections.chat << TavernKit::InjectionRegistry::Entry.new(
              id: "story_string",
              content: combined,
              position: :chat,
              depth: template.story_string_depth,
              role: template.story_string_role,
              scan: false,
              ephemeral: false,
              filter: nil,
            )

            ctx.pinned_groups["main_prompt"] = []
          else
            ctx.pinned_groups["main_prompt"] = [
              TavernKit::Prompt::Block.new(
                role: :system,
                content: combined,
                slot: :main_prompt,
                token_budget_group: :system,
                removable: false,
              ),
            ]
          end

          # Prevent duplication: story string replaces these system slots.
          %w[
            persona_description
            character_description
            character_personality
            scenario
            world_info_before_char_defs
            world_info_after_char_defs
          ].each do |key|
            ctx.pinned_groups[key] = []
          end
        end

        def story_string_anchors(injections)
          join = lambda do |entries|
            entries
              .map { |e| e.content.to_s.strip }
              .reject(&:empty?)
              .join("\n")
              .strip
          end

          {
            before: join.call(injections.before),
            after: join.call(injections.after),
          }
        end

        def join_world_info(lore_result, position:)
          entries = Array(lore_result&.activated_entries).select { |e| e.position.to_s == position }
          out = []
          entries.sort_by { |e| [-e.insertion_order.to_i, e.id.to_s] }.each do |e|
            out.unshift(e.content.to_s)
          end
          out.join("\n")
        end

        def apply_before_after_injections(ctx, injections)
          blocks = Array(ctx.pinned_groups["main_prompt"]).dup

          before_blocks = injections.before.map { |e| block_from_injection(e, slot: :main_prompt, group: :system) }
          after_blocks = injections.after.map { |e| block_from_injection(e, slot: :main_prompt, group: :system) }

          ctx.pinned_groups["main_prompt"] = before_blocks + blocks + after_blocks
        end

        def apply_in_chat_injections(ctx, injections)
          header, base_blocks = split_chat_history_header(ctx.pinned_groups.fetch("chat_history", []))

          pairs = base_blocks.map { |block| [block.to_message, block] }
          base_messages = pairs.map(&:first)
          original_blocks_by_message_id = pairs.to_h { |msg, block| [msg.object_id, block] }

          injected_messages = TavernKit::SillyTavern::InChatInjector.inject(
            base_messages,
            injections.chat,
            generation_type: ctx.generation_type,
          )

          merged_blocks = injected_messages.map do |msg|
            original_blocks_by_message_id.fetch(msg.object_id) do
              block_from_message(
                msg,
                slot: :chat_history,
                group: :system,
                removable: false,
                metadata: { source: :injection, injected: true },
              )
            end
          end

          ctx.pinned_groups["chat_history"] = header + merged_blocks
        end

        def split_chat_history_header(blocks)
          list = Array(blocks)
          return [[], []] if list.empty?

          head = []
          rest = list.dup

          while rest.any?
            b = rest.first
            break unless b.slot == :chat_history && b.token_budget_group == :system && b.removable? == false

            head << rest.shift
          end

          [head, rest]
        end

        def remove_ephemeral_injections(ctx, injections)
          reg = ctx.injection_registry
          return unless reg

          injections.ephemeral_ids.each { |id| reg.remove(id: id) }
        end

        def block_from_injection(entry, slot:, group:)
          TavernKit::Prompt::Block.new(
            role: entry.role,
            content: entry.content.to_s,
            slot: slot,
            token_budget_group: group,
            removable: false,
            metadata: { source: :injection, injection_id: entry.id },
          )
        end

        def block_from_message(message, slot:, group:, removable:, metadata:)
          msg = TavernKit::ChatHistory.coerce_message(message)
          TavernKit::Prompt::Block.new(
            role: msg.role,
            content: msg.content.to_s,
            name: msg.name,
            attachments: msg.attachments,
            message_metadata: msg.metadata,
            slot: slot,
            token_budget_group: group,
            removable: removable,
            metadata: metadata,
          )
        end

        def text_dialect?(ctx)
          ctx.dialect.to_s.strip.downcase.to_sym == :text
        end
      end
    end
  end
end
