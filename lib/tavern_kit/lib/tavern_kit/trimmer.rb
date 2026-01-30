# frozen_string_literal: true

require "json"

module TavernKit
  # Core budget enforcement for Prompt::Block arrays.
  #
  # Trimming is done by disabling removable blocks until the prompt fits
  # within the token budget. This is intentionally provider-agnostic and
  # relies on TokenEstimator.
  class Trimmer
    STRATEGIES = %i[group_order priority].freeze

    class << self
      def trim(
        blocks,
        strategy: :group_order,
        budget_tokens: nil,
        max_tokens: nil,
        reserve_tokens: 0,
        token_estimator: TavernKit::TokenEstimator.default,
        model_hint: nil,
        message_overhead_tokens: 0,
        include_message_metadata_tokens: false,
        stage: :trimming,
        on_overflow: :error
      )
        strategy = strategy.to_sym
        raise ArgumentError, "Unknown strategy: #{strategy.inspect}" unless STRATEGIES.include?(strategy)

        max_tokens = Integer(max_tokens) if !max_tokens.nil?
        reserve_tokens = Integer(reserve_tokens)
        raise ArgumentError, "reserve_tokens must be non-negative" if reserve_tokens.negative?

        budget_tokens = Integer(budget_tokens) if !budget_tokens.nil?
        budget_tokens ||= [max_tokens.to_i - reserve_tokens, 0].max
        raise ArgumentError, "budget_tokens must be non-negative" if budget_tokens.negative?

        blocks = Array(blocks)

        enabled_blocks = blocks.select(&:enabled?)
        tokens_by_id = estimate_tokens_by_id(
          enabled_blocks,
          token_estimator: token_estimator,
          model_hint: model_hint,
          message_overhead_tokens: message_overhead_tokens,
          include_message_metadata_tokens: include_message_metadata_tokens,
        )

        initial_tokens = tokens_by_id.values.sum
        return no_op_result(strategy, budget_tokens, initial_tokens, enabled_blocks) if initial_tokens <= budget_tokens

        evicted_ids =
          case strategy
          when :priority
            evict_priority(blocks, tokens_by_id, budget_tokens)
          when :group_order
            evict_group_order(blocks, tokens_by_id, budget_tokens)
          else
            {}
          end

        kept, evicted, evictions = apply_evictions(enabled_blocks, tokens_by_id, evicted_ids, strategy: strategy)
        final_tokens = initial_tokens - evictions.sum(&:token_count)

        report = TavernKit::TrimReport.new(
          strategy: strategy,
          budget_tokens: budget_tokens,
          initial_tokens: initial_tokens,
          final_tokens: final_tokens,
          eviction_count: evictions.size,
          evictions: evictions,
        )

        if final_tokens > budget_tokens
          case on_overflow&.to_sym
          when :error
            raise TavernKit::MaxTokensExceededError.new(
              estimated_tokens: final_tokens,
              max_tokens: max_tokens || (budget_tokens + reserve_tokens),
              reserve_tokens: reserve_tokens,
              stage: stage,
            )
          when :return
            # Best-effort return (callers can inspect TrimReport#over_budget?).
          else
            raise ArgumentError, "Unknown on_overflow: #{on_overflow.inspect} (expected :error or :return)"
          end
        end

        TavernKit::TrimResult.new(kept: kept, evicted: evicted, report: report)
      end

      # Rebuild the full blocks array using a TrimResult (preserves original order).
      #
      # @return [Array<Prompt::Block>]
      def apply(blocks, result)
        by_id = (Array(result.kept) + Array(result.evicted)).to_h { |b| [b.id, b] }
        Array(blocks).map { |b| by_id.fetch(b.id, b) }
      end

      private

      def no_op_result(strategy, budget_tokens, initial_tokens, enabled_blocks)
        report = TavernKit::TrimReport.new(
          strategy: strategy,
          budget_tokens: budget_tokens,
          initial_tokens: initial_tokens,
          final_tokens: initial_tokens,
          eviction_count: 0,
          evictions: [],
        )

        TavernKit::TrimResult.new(kept: enabled_blocks, evicted: [], report: report)
      end

      def estimate_tokens_by_id(blocks, token_estimator:, model_hint:, message_overhead_tokens:, include_message_metadata_tokens:)
        overhead = Integer(message_overhead_tokens)
        raise ArgumentError, "message_overhead_tokens must be non-negative" if overhead.negative?

        Array(blocks).to_h do |block|
          content_tokens = token_estimator.estimate(block.content.to_s, model_hint: model_hint)
          metadata_tokens = include_message_metadata_tokens ? estimate_message_metadata_tokens(block, token_estimator, model_hint) : 0
          [block.id, content_tokens + metadata_tokens + overhead]
        end
      end

      def estimate_message_metadata_tokens(block, token_estimator, model_hint)
        meta = block.message_metadata
        return 0 unless meta.is_a?(Hash) && meta.any?

        serialized =
          begin
            JSON.generate(meta)
          rescue JSON::GeneratorError, TypeError
            meta.to_s
          end

        token_estimator.estimate(serialized, model_hint: model_hint)
      end

      def apply_evictions(enabled_blocks, tokens_by_id, evicted_ids, strategy:)
        kept = []
        evicted = []
        records = []

        enabled_blocks.each do |block|
          next unless evicted_ids.key?(block.id)

          evicted_block = block.disable
          evicted << evicted_block

          records << TavernKit::EvictionRecord.new(
            block_id: block.id,
            slot: block.slot,
            token_count: tokens_by_id.fetch(block.id),
            reason: evicted_ids.fetch(block.id),
            budget_group: normalize_budget_group(block.token_budget_group),
            priority: (strategy == :priority ? block.priority : nil),
            source: block.metadata[:source],
          )
        end

        kept = enabled_blocks.reject { |b| evicted_ids.key?(b.id) }

        [kept, evicted, records]
      end

      def evict_priority(blocks, tokens_by_id, budget_tokens)
        protected = protected_ids(blocks, preserve_latest_user: false)

        units = build_units(blocks, tokens_by_id, protected)
        units.sort_by! { |u| [u.priority, u.first_index] }

        current = tokens_by_id.values.sum
        evicted_ids = {}

        units.each do |unit|
          break if current <= budget_tokens
          next if unit.protected

          unit.block_ids.each do |bid|
            next if evicted_ids.key?(bid)

            evicted_ids[bid] = :priority_cutoff
            current -= tokens_by_id.fetch(bid)
          end
        end

        evicted_ids
      end

      def evict_group_order(blocks, tokens_by_id, budget_tokens)
        protected = protected_ids(blocks, preserve_latest_user: true)
        current = tokens_by_id.values.sum
        evicted_ids = {}

        mapped_groups = blocks.to_h { |b| [b.id, normalize_budget_group(b.token_budget_group)] }

        # ST-style eviction order.
        [:examples, :lore, :history].each do |group|
          break if current <= budget_tokens

          group_units = build_units(blocks, tokens_by_id, protected, group: group, mapped_groups: mapped_groups)

          group_units.each do |unit|
            break if current <= budget_tokens
            next if unit.protected

            reason = unit.bundled ? :group_overflow : :budget_exceeded
            unit.block_ids.each do |bid|
              next if evicted_ids.key?(bid)

              evicted_ids[bid] = reason
              current -= tokens_by_id.fetch(bid)
            end
          end
        end

        evicted_ids
      end

      def protected_ids(blocks, preserve_latest_user:)
        protected = {}
        blocks.each do |b|
          # System budget group is never evicted in group_order mode.
          protected[b.id] = true if normalize_budget_group(b.token_budget_group) == :system
          protected[b.id] = true unless b.removable?
        end

        if preserve_latest_user
          # ST parity: preserve the latest user message in history.
          history_user = blocks.select { |b| b.enabled? && normalize_budget_group(b.token_budget_group) == :history && b.role == :user }
          protected[history_user.last.id] = true if history_user.any?
        end

        protected
      end

      Unit = Data.define(:block_ids, :token_count, :priority, :first_index, :protected, :bundled)

      def build_units(blocks, tokens_by_id, protected, group: nil, mapped_groups: nil)
        mapped_groups ||= blocks.to_h { |b| [b.id, normalize_budget_group(b.token_budget_group)] }

        groups = {}
        blocks.each_with_index do |block, idx|
          next unless block.enabled?
          next unless tokens_by_id.key?(block.id)

          budget_group = mapped_groups.fetch(block.id)
          next if group && budget_group != group

          bundle = block.metadata[:eviction_bundle]
          key = bundle ? "bundle:#{bundle}" : "block:#{block.id}"

          groups[key] ||= { ids: [], first: idx, priorities: [], protected: false, bundled: !bundle.nil? }
          g = groups[key]
          g[:ids] << block.id
          g[:priorities] << block.priority
          g[:protected] ||= protected.key?(block.id)
        end

        groups.values.map do |g|
          token_count = g[:ids].sum { |bid| tokens_by_id.fetch(bid) }
          Unit.new(
            block_ids: g[:ids],
            token_count: token_count,
            priority: g[:priorities].min || 0,
            first_index: g[:first],
            protected: g[:protected],
            bundled: g[:bundled],
          )
        end
      end

      def normalize_budget_group(group)
        group = group.to_sym
        return group if %i[system examples lore history].include?(group)

        # Default to history (evicted last) for unknown groups.
        :history
      rescue StandardError
        :history
      end
    end
  end
end
