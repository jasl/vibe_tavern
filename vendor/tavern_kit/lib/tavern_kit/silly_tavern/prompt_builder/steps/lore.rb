# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module PromptBuilder
      module Steps
      # ST World Info orchestration.
      #
      # Stage contract is pinned in `docs/contracts/prompt-orchestration.md`.
      class Lore < TavernKit::PromptBuilder::Step
        private

        DEFAULT_WORLD_INFO_BUDGET_PERCENT = 25

        def before(ctx)
          preset = ctx.preset

          ctx.scan_messages ||= build_scan_messages(ctx)
          ctx.scan_context ||= build_scan_context(ctx)
          ctx.scan_injects ||= build_scan_injects(ctx)

          books = build_books(ctx)

          budget_tokens = compute_world_info_budget_tokens(preset)

          ctx.lore_engine ||= TavernKit::SillyTavern::Lore::Engine.new(
            token_estimator: ctx.token_estimator,
            default_scan_depth: preset.world_info_depth,
            recursive_scanning: books.any?(&:recursive_scanning?),
            use_group_scoring: preset.world_info_use_group_scoring,
          )

          forced = normalize_forced_activations(ctx.forced_world_info_activations)

          input = TavernKit::SillyTavern::Lore::ScanInput.new(
            messages: ctx.scan_messages,
            books: books,
            budget: budget_tokens,
            warner: ctx.method(:warn),
            scan_context: ctx.scan_context,
            scan_injects: ctx.scan_injects,
            trigger: ctx.generation_type,
            timed_state: ctx.fetch(:timed_world_info_state, {}),
            character_name: ctx.character.name.to_s,
            character_tags: Array(ctx.character.data.tags).map(&:to_s),
            forced_activations: forced,
            min_activations: preset.world_info_min_activations,
            min_activations_depth_max: preset.world_info_min_activations_depth_max,
            turn_count: ctx.turn_count,
          )

          ctx.lore_result = ctx.lore_engine.scan(input)
          ctx.outlets = build_outlets(ctx.lore_result)

          if ctx.instrumenter
            ctx.instrument(:stat, stage: :lore, key: :world_info_activated, value: ctx.lore_result.activated_entries.size)
            ctx.instrument(:stat, stage: :lore, key: :world_info_tokens, value: ctx.lore_result.total_tokens)
          end
        end

        def build_scan_messages(ctx)
          history = TavernKit::ChatHistory.wrap(ctx.history)

          messages = []

          user_text = ctx.user_message.to_s.strip
          messages << user_text unless user_text.empty?

          # ST parity: scan buffer is newest-first (engine uses `.first(depth)`).
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

        def build_scan_context(ctx)
          persona_text = ctx.user.respond_to?(:persona_text) ? ctx.user.persona_text.to_s : ""

          char = ctx.character
          data = char.respond_to?(:data) ? char.data : char

          {
            persona_description: presence_str(persona_text),
            character_description: presence_str(data.respond_to?(:description) ? data.description : nil),
            character_personality: presence_str(data.respond_to?(:personality) ? data.personality : nil),
            character_depth_prompt: presence_str(fetch_extension(data, "depth_prompt", "character_depth_prompt", "character_notes")),
            scenario: presence_str(data.respond_to?(:scenario) ? data.scenario : nil),
            creator_notes: presence_str(data.respond_to?(:creator_notes) ? data.creator_notes : nil),
          }.compact
        end

        def build_scan_injects(ctx)
          injects = []

          reg = ctx.injection_registry
          if reg
            reg.each do |entry|
              next unless entry.scan?
              next unless entry.active_for?(ctx)

              s = entry.content.to_s.strip
              injects << s unless s.empty?
            end
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
          if persona_at_depth&.scan?
            s = persona_at_depth.content.to_s.strip
            injects << s unless s.empty?
          end

          an = TavernKit::SillyTavern::InjectionPlanner.authors_note_entry(
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
          if an&.scan?
            s = an.content.to_s.strip
            injects << s unless s.empty?
          end

          injects
        end

        def build_books(ctx)
          books = []

          Array(ctx.lore_books).each do |b|
            book = coerce_book(b)
            books << book if book
          end

          character_book = ctx.character&.data&.character_book
          if character_book
            book = coerce_book(character_book)
            books << book if book
          end

          # ST engine expects at least one book. Use an empty placeholder.
          books << TavernKit::Lore::Book.new(entries: []) if books.empty?

          books
        end

        def coerce_book(value)
          return value if value.is_a?(TavernKit::Lore::Book)

          if value.is_a?(Hash)
            # Heuristic: ST World Info JSON uses `entries[].key` and `entries[].uid`.
            if Array(value["entries"]).first.is_a?(Hash) && (value.dig("entries", 0, "key") || value.dig("entries", 0, "uid"))
              return TavernKit::SillyTavern::Lore::WorldInfoImporter.load_hash(value)
            end

            return TavernKit::Lore::Book.from_h(value)
          end

          nil
        rescue ArgumentError, TavernKit::SillyTavern::LoreParseError
          nil
        end

        def compute_world_info_budget_tokens(preset)
          max_context = preset.context_window_tokens.to_i
          pct = preset.world_info_budget
          pct = DEFAULT_WORLD_INFO_BUDGET_PERCENT if pct.nil?
          pct = pct.to_i
          pct = DEFAULT_WORLD_INFO_BUDGET_PERCENT if pct > 100

          budget = (pct * max_context / 100.0).round
          budget = 1 if budget <= 0

          cap = preset.world_info_budget_cap.to_i
          budget = cap if cap.positive? && budget > cap

          budget
        end

        def normalize_forced_activations(list)
          Array(list).filter_map do |raw|
            next raw.to_s if raw.is_a?(String)

            acc = TavernKit::Utils::HashAccessor.wrap(raw.is_a?(Hash) ? raw : {})
            acc.fetch(:id, :entry_id, :entryId, :uid, default: nil)&.to_s
          end
        end

        def build_outlets(lore_result)
          grouped = Hash.new { |h, k| h[k] = [] }

          Array(lore_result&.activated_entries).each do |entry|
            next unless entry.position.to_s == "outlet"

            ext = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry)
            name = ext.outlet_name
            next unless name

            content = entry.content.to_s
            grouped[name] << content unless content.strip.empty?
          end

          grouped
            .transform_values { |v| v.join("\n").strip }
            .reject { |_k, v| v.empty? }
        end

        def fetch_extension(data, *keys)
          ext = data.respond_to?(:extensions) ? data.extensions : nil
          return nil unless ext.is_a?(Hash)

          acc = TavernKit::Utils::HashAccessor.wrap(ext)
          keys.each do |k|
            v = acc.fetch(k, default: nil)
            next if v.nil?

            # ST parity: depth_prompt is typically a nested object
            # (`extensions.depth_prompt.prompt`). Scan only the prompt text.
            if v.is_a?(Hash)
              nested = TavernKit::Utils::HashAccessor.wrap(v).fetch(:prompt, default: nil)
              return nested unless nested.nil?
              next
            end

            return v
          end
          nil
        end

        def presence_str(value)
          s = value.to_s
          s.strip.empty? ? nil : s
        end
      end
      end
    end
  end
end
