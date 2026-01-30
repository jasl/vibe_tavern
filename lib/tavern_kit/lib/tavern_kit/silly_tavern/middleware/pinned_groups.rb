# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Middleware
      # Wave 4: resolves ST pinned prompt groups into block arrays.
      class PinnedGroups < TavernKit::Prompt::Middleware::Base
        private

        WI_POSITIONS = {
          "before_char_defs" => :world_info_before_char_defs,
          "after_char_defs" => :world_info_after_char_defs,
          "before_example_messages" => :world_info_before_example_messages,
          "after_example_messages" => :world_info_after_example_messages,
        }.freeze

        def before(ctx)
          preset = ctx.preset

          fields = effective_character_fields(ctx)

          by_wi_position = world_info_by_position(ctx.lore_result)

          groups = {}

          Array(ctx.prompt_entries).each do |entry|
            next unless entry.pinned?

            groups[entry.id] = build_group_blocks(entry, ctx, preset, fields, by_wi_position)
          end

          ctx.pinned_groups = groups
          ctx.instrument(:stat, stage: :pinned_groups, key: :pinned_groups, value: groups.size)
        end

        def build_group_blocks(entry, ctx, preset, fields, by_wi_position)
          id = entry.id

          case id
          when "main_prompt"
            content = effective_main_prompt(preset, ctx.character)
            system_blocks(entry, content, slot: :main_prompt, group: :system, removable: false)
          when "post_history_instructions"
            content = effective_post_history_instructions(preset, ctx.character)
            system_blocks(entry, content, slot: :post_history_instructions, group: :system, removable: false)
          when "enhance_definitions"
            system_blocks(entry, preset.enhance_definitions, slot: :enhance_definitions, group: :system, removable: false)
          when "auxiliary_prompt"
            system_blocks(entry, preset.auxiliary_prompt, slot: :auxiliary_prompt, group: :system, removable: false)
          when "persona_description"
            persona_position = ctx.fetch(:persona_position, :in_prompt).to_s.strip.downcase.to_sym
            persona_text = ctx.user.respond_to?(:persona_text) ? ctx.user.persona_text.to_s.strip : ""
            return [] unless persona_position == :in_prompt

            system_blocks(entry, persona_text, slot: :persona_description, group: :system, removable: false)
          when "character_description"
            system_blocks(entry, fields[:description], slot: :character_description, group: :system, removable: false)
          when "character_personality"
            return [] if fields[:personality].to_s.strip.empty?

            system_blocks(entry, preset.personality_format, slot: :character_personality, group: :system, removable: false)
          when "scenario"
            return [] if fields[:scenario].to_s.strip.empty?

            system_blocks(entry, preset.scenario_format, slot: :scenario, group: :system, removable: false)
          when "chat_examples"
            build_chat_examples(entry, ctx, preset, raw: fields[:mes_example], slot: :chat_examples)
          when "chat_history"
            build_chat_history(entry, ctx, preset)
          when "world_info_before_char_defs", "world_info_after_char_defs", "world_info_before_example_messages", "world_info_after_example_messages"
            slot = id.to_sym
            strings = by_wi_position.fetch(slot, [])
            content = format_world_info(strings.join("\n"), preset.wi_format)
            system_blocks(entry, content, slot: slot, group: :lore, removable: true)
          else
            resolve_custom_pinned(entry, ctx)
          end
        end

        def system_blocks(entry, content, slot:, group:, removable:)
          s = content.to_s
          return [] if s.strip.empty?

          [
            TavernKit::Prompt::Block.new(
              role: entry.role,
              content: s,
              slot: slot,
              token_budget_group: group,
              removable: removable,
            ),
          ]
        end

        def resolve_custom_pinned(entry, ctx)
          resolver = ctx.preset.pinned_group_resolver
          content = nil

          if resolver.respond_to?(:call)
            content =
              if resolver.arity >= 2
                resolver.call(entry.id, ctx)
              else
                resolver.call(entry.id)
              end
          end

          content = entry.content if content.nil?

          system_blocks(entry, content, slot: entry.id.to_sym, group: :system, removable: false)
        rescue StandardError => e
          ctx.warn("PinnedGroup resolver error: #{e.class}: #{e.message}")
          system_blocks(entry, entry.content, slot: entry.id.to_sym, group: :system, removable: false)
        end

        def effective_main_prompt(preset, character)
          if preset.prefer_char_prompt == true
            override = character&.data&.system_prompt.to_s
            return override unless override.strip.empty?
          end

          preset.main_prompt.to_s
        end

        def effective_post_history_instructions(preset, character)
          if preset.prefer_char_instructions == true
            override = character&.data&.post_history_instructions.to_s
            return override unless override.strip.empty?
          end

          preset.post_history_instructions.to_s
        end

        def build_chat_examples(entry, ctx, preset, raw:, slot:)
          examples_raw = raw.to_s.strip
          return [] if examples_raw.empty?

          instruct = preset.effective_instruct
          context_template = preset.effective_context_template

          dialect = ctx.dialect
          main_api = dialect && dialect.to_sym == :openai ? "openai" : nil

          blocks = []

          # Matches ST: a header is always emitted when examples exist.
          header = preset.new_example_chat_prompt.to_s
          if !header.strip.empty?
            blocks << TavernKit::Prompt::Block.new(
              role: :system,
              content: header,
              slot: slot,
              token_budget_group: :examples,
              removable: true,
              metadata: { eviction_bundle: "examples:header" },
            )
          end

          TavernKit::SillyTavern::ExamplesParser.parse(
            examples_raw,
            example_separator: context_template.example_separator,
            is_instruct: instruct.enabled?,
            main_api: main_api,
          ).each_with_index do |text, idx|
            blocks << TavernKit::Prompt::Block.new(
              role: entry.role,
              content: text,
              slot: slot,
              token_budget_group: :examples,
              removable: true,
              metadata: { eviction_bundle: "examples:dialogue:#{idx}" },
            )
          end

          blocks
        end

        def build_chat_history(entry, ctx, preset)
          history = TavernKit::ChatHistory.wrap(ctx.history)
          blocks = []

          new_chat_prompt =
            if ctx.group
              preset.new_group_chat_prompt.to_s
            else
              preset.new_chat_prompt.to_s
            end

          if !new_chat_prompt.strip.empty?
            blocks << TavernKit::Prompt::Block.new(
              role: :system,
              content: new_chat_prompt,
              slot: :chat_history,
              token_budget_group: :system,
              removable: false,
            )
          end

          history.each do |msg|
            blocks << block_from_message(msg, slot: :chat_history, group: :history, removable: true)
          end

          user_text = ctx.user_message.to_s
          if user_text.strip.empty?
            last = history.last(1).first
            send_if_empty = preset.send_if_empty.to_s
            if last&.role&.to_sym == :assistant && !send_if_empty.strip.empty?
              blocks << TavernKit::Prompt::Block.new(
                role: :user,
                content: send_if_empty,
                slot: :chat_history,
                token_budget_group: :history,
                removable: true,
                metadata: { source: :send_if_empty },
              )
            end
          else
            blocks << TavernKit::Prompt::Block.new(
              role: :user,
              content: user_text,
              slot: :chat_history,
              token_budget_group: :history,
              removable: true,
              metadata: { source: :user_message },
            )
          end

          blocks
        rescue ArgumentError
          []
        end

        def block_from_message(message, slot:, group:, removable:)
          msg = TavernKit::ChatHistory.coerce_message(message)
          TavernKit::Prompt::Block.new(
            role: msg.role.to_sym,
            content: msg.content.to_s,
            name: msg.name,
            attachments: msg.attachments,
            message_metadata: msg.metadata,
            slot: slot,
            token_budget_group: group,
            removable: removable,
          )
        end

        def format_world_info(value, format)
          v = value.to_s
          return "" if v.strip.empty?

          f = format.to_s
          return v if f.strip.empty?

          f.gsub(/\{0\}/, v)
        end

        def world_info_by_position(lore_result)
          entries = Array(lore_result&.activated_entries)
          return WI_POSITIONS.values.to_h { |k| [k, []] } if entries.empty?

          grouped = Hash.new { |h, k| h[k] = [] }

          # ST order: sort by insertion_order desc, then unshift (=> ascending final).
          sorted = entries.sort_by { |e| [-e.insertion_order.to_i, e.id.to_s] }

          sorted.each do |entry|
            slot = WI_POSITIONS[entry.position.to_s]
            next unless slot

            grouped[slot].unshift(entry.content.to_s)
          end

          WI_POSITIONS.values.each { |slot| grouped[slot] ||= [] }
          grouped
        end

        def effective_character_fields(ctx)
          group = ctx.group

          if group
            merged = build_group_card(group, ctx.character)
            if merged
              return {
                description: merged[:description],
                personality: merged[:personality],
                scenario: merged[:scenario],
                mes_example: merged[:mes_examples] || merged[:mesExamples],
              }
            end
          end

          data = ctx.character.data

          {
            description: data.description.to_s,
            personality: data.personality.to_s,
            scenario: data.scenario.to_s,
            mes_example: data.mes_example.to_s,
          }
        end

        def build_group_card(group, current_character)
          cfg = TavernKit::Utils::HashAccessor.wrap(group.is_a?(Hash) ? group : {})

          members = Array(cfg.fetch(:members, default: []))
          return nil if members.empty?

          config = {
            generation_mode: cfg.fetch(:generation_mode, :generationMode, default: :swap),
            activation_strategy: cfg.fetch(:activation_strategy, :activationStrategy, default: :natural),
            members: members,
            disabled_members: Array(cfg.fetch(:disabled_members, :disabledMembers, default: [])),
            join_prefix: cfg.fetch(:join_prefix, :joinPrefix, default: ""),
            join_suffix: cfg.fetch(:join_suffix, :joinSuffix, default: ""),
          }

          characters_by_id = cfg.fetch(:characters_by_id, :charactersById, default: nil)
          return nil unless characters_by_id.is_a?(Hash)

          current_speaker_id = cfg.fetch(:current_speaker_id, :currentSpeakerId, default: nil) || current_character&.name

          overrides = {}
          overrides[:scenario] = cfg.fetch(:scenario, :scenario_override, :scenarioOverride, default: "")
          overrides[:mes_examples] = cfg.fetch(:mes_examples, :mes_example, :mesExample, default: "")

          result = TavernKit::SillyTavern::GroupContext.merge_cards(
            config: config,
            characters_by_id: characters_by_id,
            current_speaker_id: current_speaker_id,
            overrides: overrides,
          )

          result&.transform_keys { |k| TavernKit::Utils.underscore(k.to_s).to_sym }
        rescue StandardError
          nil
        end
      end
    end
  end
end
