# frozen_string_literal: true

require "js_regex_to_ruby"
require_relative "engine/buffer"

module TavernKit
  module SillyTavern
    module Lore
      # SillyTavern World Info scanning engine (Wave 3).
      #
      # Implements the core scanning loop: keyword matching, recursion, delayed recursion,
      # timed effects, min activations, inclusion groups, and token budgeting.
      #
      # Entry identity: ST treats world info entries as (world, uid) pairs. To avoid id collisions
      # across multiple books, this engine namespaces entry ids as "world.uid", using:
      # - book.extensions["world"] (preferred) or book.name
      # - fallback: "book#{index}"
      class Engine < TavernKit::Lore::Engine::Base
        DEFAULT_MAX_RECURSION_STEPS = 3
        HARD_MAX_RECURSION_STEPS = 10

        MAX_SCAN_DEPTH = 1_000
        MAX_RECURSE_BUFFER_BYTES = 1_000_000

        MATCHER = "\x01"
        JOINER = "\n#{MATCHER}"

        ScanEntry = Struct.new(:entry, :decorators, :ext, :order, keyword_init: true)

        def self.sort_entries(global:, character:, chat:, persona:, strategy:)
          sort_fn = lambda do |list|
            Array(list).sort_by do |entry|
              order =
                if entry.respond_to?(:insertion_order)
                  entry.insertion_order
                elsif entry.is_a?(Hash)
                  TavernKit::Utils::HashAccessor.wrap(entry).fetch(:order, :insertion_order, :insertionOrder, default: 0).to_i
                else
                  0
                end

              -order.to_i
            end
          end

          global_sorted = sort_fn.call(global)
          char_sorted = sort_fn.call(character)

          base =
            case strategy.to_sym
            when :character_lore_first, :character_first
              char_sorted + global_sorted
            when :global_lore_first, :global_first
              global_sorted + char_sorted
            when :evenly
              sort_fn.call(global_sorted + char_sorted)
            else
              sort_fn.call(global_sorted + char_sorted)
            end

          sort_fn.call(chat) + sort_fn.call(persona) + base
        end

        def self.match_entry(entry, text, case_sensitive: false, match_whole_words: true)
          h = entry.is_a?(Hash) ? entry : entry.respond_to?(:to_h) ? entry.to_h : {}
          ha = TavernKit::Utils::HashAccessor.wrap(h)

          keys = Array(ha.fetch(:keys, default: [])).map(&:to_s)
          return false if keys.empty?

          scan = text.to_s
          scan_downcase = case_sensitive ? nil : scan.downcase
          primary_matched =
            keys.any? do |k|
              Buffer.match_pre_normalized?(scan, scan_downcase, k, nil, case_sensitive: case_sensitive, match_whole_words: match_whole_words)
            end
          return false unless primary_matched

          selective = ha.bool(:selective, default: false)
          secondary = Array(ha.fetch(:secondary_keys, :secondaryKeys, default: [])).map(&:to_s).map(&:strip).reject(&:empty?)
          return true unless selective == true && secondary.any?

          ext = TavernKit::Utils::HashAccessor.wrap(ha.fetch(:extensions, default: {}))
          logic =
            case ext.fetch(:selective_logic, :selectiveLogic, default: nil)
            when 0, "0" then :and_any
            when 1, "1" then :not_all
            when 2, "2" then :not_any
            when 3, "3" then :and_all
            else
              raw = ext.fetch(:selective_logic, :selectiveLogic, default: nil)
              raw.nil? ? :and_any : TavernKit::Utils.underscore(raw).to_sym
            end

          has_any = false
          has_all = true

          secondary.each do |key|
            matched = Buffer.match_pre_normalized?(scan, scan_downcase, key, nil, case_sensitive: case_sensitive, match_whole_words: match_whole_words)

            has_any ||= matched
            has_all &&= matched

            return true if logic == :and_any && matched
            return true if logic == :not_all && !matched
          end

          return true if logic == :not_any && !has_any
          return true if logic == :and_all && has_all

          false
        end

        def self.apply_budget(entries:, max_context:, budget_percent:, budget_cap: 0)
          list = Array(entries)
          max = max_context.to_i
          pct = budget_percent.to_f
          cap = budget_cap.to_i

          budget = (pct * max / 100.0).round
          budget = 1 if budget <= 0
          budget = cap if cap.positive? && budget > cap

          used = 0
          list.filter_map do |entry|
            h = entry.is_a?(Hash) ? entry : entry.respond_to?(:to_h) ? entry.to_h : {}
            ha = TavernKit::Utils::HashAccessor.wrap(h)
            tokens = ha.fetch(:tokens, default: 0).to_i
            ignore = ha.bool(:ignore_budget, :ignoreBudget, default: false)

            if ignore
              used += tokens
              entry
            elsif (used + tokens) >= budget
              nil
            else
              used += tokens
              entry
            end
          end
        end

        def self.scan_state(entry, recursion:, current_delay_level: 1)
          h = entry.is_a?(Hash) ? entry : entry.respond_to?(:to_h) ? entry.to_h : {}
          ha = TavernKit::Utils::HashAccessor.wrap(h)
          ext = TavernKit::Utils::HashAccessor.wrap(ha.fetch(:extensions, default: {}))

          exclude_recursion = ext.bool(:exclude_recursion, :excludeRecursion, default: false)
          delay_raw = ext.fetch(:delay_until_recursion, :delayUntilRecursion, default: nil)

          delay_level =
            if delay_raw.nil? || delay_raw == false
              nil
            elsif delay_raw == true
              1
            else
              i = delay_raw.to_i
              i.positive? ? i : 1
            end

          if recursion == true
            return :excluded if exclude_recursion == true
            return :delayed if delay_level && delay_level.to_i > current_delay_level.to_i

            :eligible
          else
            delay_level ? :delayed : :eligible
          end
        end

        def initialize(
          token_estimator: TavernKit::TokenEstimator.default,
          match_whole_words: true,
          case_sensitive: false,
          default_scan_depth: nil,
          recursive_scanning: false,
          max_recursion_steps: DEFAULT_MAX_RECURSION_STEPS,
          use_group_scoring: false,
          rng: Random.new,
          force_activate: nil,
          on_scan_done: nil
        )
          unless token_estimator.respond_to?(:estimate)
            raise ArgumentError, "token_estimator must respond to #estimate"
          end
          @token_estimator = token_estimator

          unless match_whole_words == true || match_whole_words == false
            raise ArgumentError, "match_whole_words must be a Boolean, got: #{match_whole_words.class}"
          end
          @match_whole_words = match_whole_words

          unless case_sensitive == true || case_sensitive == false
            raise ArgumentError, "case_sensitive must be a Boolean, got: #{case_sensitive.class}"
          end
          @case_sensitive = case_sensitive

          @default_scan_depth = default_scan_depth.nil? ? nil : default_scan_depth.to_i
          @recursive_scanning = recursive_scanning == true

          @max_recursion_steps = [[max_recursion_steps.to_i, 0].max, HARD_MAX_RECURSION_STEPS].min
          @use_group_scoring = use_group_scoring == true

          @rng = rng || Random.new
          @force_activate = force_activate
          @on_scan_done = on_scan_done
        end

        def scan(input)
          books = Array(input.books).compact
          raise ArgumentError, "SillyTavern::Lore::Engine#scan requires input.books" if books.empty?

          messages = Array(input.messages).map(&:to_s)
          budget = input.budget.nil? ? nil : input.budget.to_i

          scan_context = input.respond_to?(:scan_context) ? input.scan_context : {}
          scan_injects = input.respond_to?(:scan_injects) ? input.scan_injects : []
          trigger = input.respond_to?(:trigger) ? input.trigger : :normal

          character_name = input.respond_to?(:character_name) ? input.character_name : nil
          character_tags = input.respond_to?(:character_tags) ? input.character_tags : []

          forced_activations = input.respond_to?(:forced_activations) ? input.forced_activations : []
          min_activations = input.respond_to?(:min_activations) ? input.min_activations.to_i : 0
          min_activations_depth_max = input.respond_to?(:min_activations_depth_max) ? input.min_activations_depth_max.to_i : 0
          turn_count = input.respond_to?(:turn_count) ? input.turn_count.to_i : messages.length

          timed_state = input.respond_to?(:timed_state) ? input.timed_state : {}

          sorted_entries = build_entries(books)
          return empty_result if sorted_entries.empty?

          entry_index = sorted_entries.each_with_index.each_with_object({}) do |(se, idx), map|
            map[se.entry.id.to_s] = idx
          end

          default_depth = @default_scan_depth || messages.length
          buffer = Buffer.new(
            messages: messages,
            default_depth: default_depth,
            scan_context: scan_context,
            scan_injects: scan_injects,
          )

          timed_effects = TimedEffects.new(
            turn_count: turn_count,
            entries: sorted_entries.map(&:entry),
            timed_state: timed_state,
          ).check!

          forced_set = Array(forced_activations).map(&:to_s).to_h { |id| [id, true] }
          min_activations = [min_activations, 0].max
          min_activations_depth_max = [min_activations_depth_max, 0].max
          min_activations_enabled = min_activations.positive?

          recursive_enabled = @recursive_scanning

          delay_levels = sorted_entries.filter_map { |se| se.ext.delay_until_recursion_level }.uniq.sort
          current_delay_level = delay_levels.shift || 0

          activated_by_id = {}
          failed_probability = {}
          used_tokens = 0
          token_budget_overflowed = false

          loop_count = 0
          scan_state = :initial

          while scan_state
            break if @max_recursion_steps.positive? && loop_count >= @max_recursion_steps

            loop_count += 1
            activated_now = []

            sorted_entries.each do |se|
              id = se.entry.id.to_s
              next if failed_probability[id]
              next if activated_by_id.key?(id)
              next unless se.entry.enabled?

              next unless se.ext.triggered_by?(trigger)
              next unless se.ext.matches_character?(character_name: character_name, character_tags: character_tags)

              is_sticky = timed_effects.sticky_active?(id)
              is_cooldown = timed_effects.cooldown_active?(id)
              is_delay = timed_effects.delay_active?(se.entry)

              next if is_delay
              next if is_cooldown && !is_sticky

              if scan_state != :recursion && se.ext.delay_until_recursion? && !is_sticky
                next
              end

              if scan_state == :recursion && se.ext.delay_until_recursion? && !is_sticky
                lvl = se.ext.delay_until_recursion_level || 1
                next if lvl > current_delay_level
              end

              if scan_state == :recursion && recursive_enabled && se.ext.exclude_recursion? && !is_sticky
                next
              end

              if se.decorators.include?("@@activate")
                activated_now << se
                next
              end

              if se.decorators.include?("@@dont_activate")
                next
              end

              if forced_set[id]
                activated_now << se
                next
              end

              if @force_activate
                forced = @force_activate.call(se.entry, scan_state: scan_state, input: input)
                case forced
                when TavernKit::Lore::Entry
                  activated_now << ScanEntry.new(
                    entry: forced,
                    decorators: se.decorators,
                    ext: EntryExtensions.wrap(forced),
                    order: forced.insertion_order.to_i,
                  )
                  next
                when true
                  activated_now << se
                  next
                end
              end

              if se.entry.constant?
                activated_now << se
                next
              end

              if is_sticky
                activated_now << se
                next
              end

              scan_text = buffer.get(se.ext, scan_state)
              next if scan_text.empty?

              primary_match = first_primary_match(se.entry.keys, scan_text, se)
              next unless primary_match

              if needs_secondary_check?(se.entry)
                matched = match_secondary(se.entry, scan_text, se)
                next unless matched
              end

              activated_now << se
            end

            activated_now.sort_by! do |se|
              sticky_rank = timed_effects.sticky_active?(se.entry.id.to_s) ? 0 : 1
              [sticky_rank, entry_index.fetch(se.entry.id.to_s, 0)]
            end

            filter_by_inclusion_groups!(
              activated_now,
              already_activated: activated_by_id.values,
              buffer: buffer,
              scan_state: scan_state,
              timed_effects: timed_effects,
            )

            ignores_budget_left = activated_now.count { |se| se.ext.ignore_budget? }

            successful_for_recursion = []

            activated_now.each do |se|
              id = se.entry.id.to_s
              ignores_budget_left -= 1 if se.ext.ignore_budget?

              if token_budget_overflowed && !se.ext.ignore_budget?
                next if ignores_budget_left.positive?
                break
              end

              unless passes_probability?(se, sticky_active: timed_effects.sticky_active?(id))
                failed_probability[id] = true
                next
              end

              tokens = estimate_tokens(se.entry.content)

              if !budget.nil? && !se.ext.ignore_budget? && (used_tokens + tokens) >= budget
                token_budget_overflowed = true
                next
              end

              activated_by_id[id] = se
              used_tokens += tokens

              successful_for_recursion << se unless se.ext.prevent_recursion?
            end

            next_state = nil

            if recursive_enabled && !token_budget_overflowed && successful_for_recursion.any?
              next_state = :recursion
            end

            if recursive_enabled && !token_budget_overflowed && scan_state == :min_activations && buffer.has_recurse?
              next_state = :recursion
            end

            if next_state.nil? && !token_budget_overflowed && min_activations_enabled && activated_by_id.size < min_activations
              over_max =
                (min_activations_depth_max.positive? && buffer.depth > min_activations_depth_max) ||
                  (buffer.depth > messages.length)

              unless over_max
                next_state = :min_activations
                buffer.advance_scan
              end
            end

            if next_state.nil? && delay_levels.any?
              next_state = :recursion
              current_delay_level = delay_levels.shift
            end

            cur_state = scan_state
            scan_state = next_state

            if scan_state
              text = successful_for_recursion.map { |se| se.entry.content }.join("\n")
              buffer.add_recurse(text) if !text.empty?
            end

            if @on_scan_done
              successful_now = activated_now.select { |se| activated_by_id.key?(se.entry.id.to_s) }.map(&:entry)
              @on_scan_done.call(
                state: { current: cur_state, next: scan_state, loop_count: loop_count },
                new: { all: activated_now.map(&:entry), successful: successful_now },
                activated: { entries: activated_by_id.values.map(&:entry) },
                recursion_delay: { current_level: current_delay_level, available_levels: delay_levels.dup },
                budget: { limit: budget, used_tokens: used_tokens, overflowed: token_budget_overflowed },
                buffer: buffer,
                timed_effects: timed_effects,
              )
            end
          end

          activated_entries = activated_by_id.values.map(&:entry)
          timed_effects.set_effects!(activated_entries)

          TavernKit::Lore::Result.new(
            activated_entries: activated_entries,
            total_tokens: used_tokens,
            trim_report: nil,
          )
        end

        private

        def empty_result
          TavernKit::Lore::Result.new(activated_entries: [], total_tokens: 0, trim_report: nil)
        end

        def build_entries(books)
          list = []

          books.each_with_index do |book, book_idx|
            world = book_world(book, book_idx)

            Array(book.entries).each_with_index do |entry, entry_idx|
              decorators, content = DecoratorParser.parse(entry.content)
              effective = content == entry.content ? entry : entry.with(content: content)

              effective = ensure_entry_key(effective, world: world, entry_idx: entry_idx)

              list << ScanEntry.new(
                entry: effective,
                decorators: decorators,
                ext: EntryExtensions.wrap(effective),
                order: effective.insertion_order.to_i,
              )
            end
          end

          list.sort_by { |se| [-se.order, se.entry.id.to_s] }
        end

        def book_world(book, idx)
          ext = book.respond_to?(:extensions) ? book.extensions : {}
          acc = TavernKit::Utils::HashAccessor.wrap(ext.is_a?(Hash) ? ext : {})

          v = acc["world", "st_world", "source", "id"] || (book.respond_to?(:name) ? book.name : nil)
          s = v.to_s.strip
          s.empty? ? "book#{idx}" : s
        end

        def ensure_entry_key(entry, world:, entry_idx:)
          raw = entry.respond_to?(:id) ? entry.id : nil
          uid = raw.to_s.strip
          uid = entry_idx.to_s if uid.empty?

          # Assume it's already namespaced (world.uid) if it includes a separator.
          return entry if uid.include?(".")

          entry.with(id: "#{world}.#{uid}")
        end

        def first_primary_match(keys, scan_text, scan_entry)
          scan_text_downcase = case_sensitive(scan_entry) ? nil : scan_text.to_s.downcase

          Array(keys).find do |key|
            k = key.to_s.strip
            next false if k.empty?

            Buffer.match_pre_normalized?(
              scan_text,
              scan_text_downcase,
              k,
              scan_entry,
              case_sensitive: case_sensitive(scan_entry),
              match_whole_words: match_whole_words(scan_entry),
            )
          end
        end

        def needs_secondary_check?(entry)
          entry.selective == true && Array(entry.secondary_keys).any?
        end

        def match_secondary(entry, scan_text, scan_entry)
          secondary = Array(entry.secondary_keys).map { |k| k.to_s.strip }.reject(&:empty?)
          return true if secondary.empty?

          scan_text_downcase = case_sensitive(scan_entry) ? nil : scan_text.to_s.downcase
          logic = scan_entry.ext.selective_logic

          has_any = false
          has_all = true

          secondary.each do |key|
            matched =
              Buffer.match_pre_normalized?(
                scan_text,
                scan_text_downcase,
                key,
                scan_entry,
                case_sensitive: case_sensitive(scan_entry),
                match_whole_words: match_whole_words(scan_entry),
              )

            has_any ||= matched
            has_all &&= matched

            return true if logic == :and_any && matched
            return true if logic == :not_all && !matched
          end

          return true if logic == :not_any && !has_any
          return true if logic == :and_all && has_all

          false
        end

        def passes_probability?(scan_entry, sticky_active:)
          return true unless scan_entry.ext.use_probability?
          return true if scan_entry.ext.probability >= 100
          return true if sticky_active

          (@rng.rand * 100) <= scan_entry.ext.probability
        end

        def estimate_tokens(text)
          @token_estimator.estimate(text.to_s)
        end

        def case_sensitive(scan_entry)
          entry = scan_entry.entry
          return entry.case_sensitive if entry.case_sensitive == true || entry.case_sensitive == false

          @case_sensitive
        end

        def match_whole_words(scan_entry)
          v = scan_entry.ext.match_whole_words
          v.nil? ? @match_whole_words : v
        end

        def filter_by_inclusion_groups!(entries, already_activated:, buffer:, scan_state:, timed_effects:)
          grouped = {}

          entries.each do |se|
            next if se.ext.group_names.empty?

            se.ext.group_names.each do |name|
              (grouped[name] ||= []) << se
            end
          end

          return if grouped.empty?

          has_sticky = {}

          grouped.each do |name, group|
            has_sticky[name] = false

            sticky_entries = group.select { |se| timed_effects.sticky_active?(se.entry.id.to_s) }
            if sticky_entries.any?
              group.dup.each do |se|
                next if sticky_entries.include?(se)

                entries.delete(se)
                group.delete(se)
              end
              has_sticky[name] = true
            end

            group.dup.each do |se|
              if timed_effects.cooldown_active?(se.entry.id.to_s) || timed_effects.delay_active?(se.entry)
                entries.delete(se)
                group.delete(se)
              end
            end
          end

          filter_groups_by_scoring!(grouped, entries, buffer, scan_state, has_sticky)

          grouped.each do |name, group|
            next if has_sticky[name]

            if already_activated.any? { |se| se.ext.group.to_s == name }
              group.each { |se| entries.delete(se) }
              next
            end

            next if group.length <= 1

            prios = group.select { |se| se.ext.group_override? }.sort_by { |se| [-se.order, se.entry.id.to_s] }
            if prios.any?
              winner = prios.first
              group.each { |se| entries.delete(se) unless se == winner }
              next
            end

            total_weight = group.sum { |se| se.ext.group_weight }
            roll = @rng.rand * total_weight
            current = 0
            winner = nil

            group.each do |se|
              current += se.ext.group_weight
              if roll <= current
                winner = se
                break
              end
            end

            group.each { |se| entries.delete(se) unless se == winner }
          end
        end

        def filter_groups_by_scoring!(grouped, entries, buffer, scan_state, has_sticky)
          grouped.each do |name, group|
            next if group.empty?
            next if has_sticky[name]

            any_entry_scored = group.any? do |se|
              explicit = se.ext.use_group_scoring
              explicit == true
            end

            next unless @use_group_scoring || any_entry_scored

            scores = group.map { |se| buffer.score(se, scan_state, case_sensitive: case_sensitive(se), match_whole_words: match_whole_words(se)) }
            max_score = scores.max || 0

            group.each_with_index do |se, idx|
              explicit = se.ext.use_group_scoring
              is_scored = explicit.nil? ? @use_group_scoring : explicit
              next unless is_scored

              next unless scores[idx] < max_score

              entries.delete(se)
            end

            group.reject! { |se| !entries.include?(se) }
          end
        end
        # Buffer extracted to `silly_tavern/lore/engine/buffer.rb` (Wave 6).
      end
    end
  end
end
