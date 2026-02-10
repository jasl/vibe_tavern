# frozen_string_literal: true

require "digest"
require "json"

require_relative "block"

module TavernKit
  module Prompt
    # A prompt plan is a sequence of Prompt::Block objects.
    #
    # Plans make it easier to:
    # - inspect/debug the built prompt (all blocks including disabled)
    # - filter to only enabled blocks for LLM consumption
    # - insert custom content at specific points
    class Plan
      attr_reader :blocks, :outlets, :lore_result, :trim_report, :greeting, :greeting_index, :warnings, :trace, :llm_options

      def initialize(
        blocks:,
        outlets: {},
        lore_result: nil,
        trim_report: nil,
        greeting: nil,
        greeting_index: nil,
        warnings: nil,
        trace: nil,
        llm_options: nil
      )
        @blocks = Array(blocks).dup.freeze
        @outlets = (outlets || {}).dup.freeze
        @lore_result = lore_result
        @trim_report = trim_report
        @greeting = greeting
        @greeting_index = greeting_index
        @warnings = Array(warnings).compact.map(&:to_s).freeze
        @trace = trace
        @llm_options = (llm_options || {}).dup.freeze

        freeze
      end

      # Create a new Plan with updated attributes (immutable update).
      #
      # This is intended for middleware that needs to adjust blocks or metadata
      # after a plan has been assembled.
      def with(
        blocks: @blocks,
        outlets: @outlets,
        lore_result: @lore_result,
        trim_report: @trim_report,
        greeting: @greeting,
        greeting_index: @greeting_index,
        warnings: @warnings,
        trace: @trace,
        llm_options: @llm_options
      )
        Plan.new(
          blocks: blocks,
          outlets: outlets,
          lore_result: lore_result,
          trim_report: trim_report,
          greeting: greeting,
          greeting_index: greeting_index,
          warnings: warnings,
          trace: trace,
          llm_options: llm_options,
        )
      end

      def with_blocks(blocks)
        with(blocks: blocks)
      end

      # Append a block to the plan.
      def append_block(block)
        insert_at_index(blocks.size, block)
      end

      # Insert a block before the first block with the given slot.
      #
      # If the slot is not found, the block is appended.
      def insert_before(slot:, block:)
        slot = slot&.to_sym
        idx = blocks.find_index { |b| b.slot == slot }
        idx ||= blocks.size
        insert_at_index(idx, block)
      end

      # Insert a block after the last block with the given slot.
      #
      # If the slot is not found, the block is appended.
      def insert_after(slot:, block:)
        slot = slot&.to_sym
        idx = blocks.rindex { |b| b.slot == slot }
        idx = idx ? idx + 1 : blocks.size
        insert_at_index(idx, block)
      end

      def greeting?
        !@greeting.nil?
      end

      # Returns only enabled blocks.
      # @return [Array<Block>]
      def enabled_blocks
        @blocks.select(&:enabled?)
      end

      # Convert enabled blocks to Message objects.
      # @return [Array<Message>]
      def messages
        merge_in_chat_blocks_for_output(enabled_blocks).map(&:to_message)
      end

      # Convert enabled blocks to the specified dialect format.
      # Dialects are loaded lazily to avoid circular dependencies.
      def to_messages(dialect: :openai, squash_system_messages: false, **dialect_opts)
        dialect_sym = dialect.to_sym

        output_blocks = merge_in_chat_blocks_for_output(enabled_blocks)
        if squash_system_messages && dialect_sym == :openai
          output_blocks = squash_system_blocks(output_blocks)
        end

        msgs = output_blocks.map(&:to_message)

        if defined?(Dialects)
          Dialects.convert(msgs, dialect: dialect_sym, **dialect_opts)
        else
          # Fallback: simple message hash array
          msgs.map(&:to_h)
        end
      end

      # Stable SHA256 fingerprint derived from final output messages.
      #
      # Intended for caching/debugging. Excludes random block ids by design.
      def fingerprint(dialect: :openai, squash_system_messages: false, **dialect_opts)
        Digest::SHA256.hexdigest(
          JSON.generate(
            {
              messages: to_messages(dialect: dialect, squash_system_messages: squash_system_messages, **dialect_opts),
              llm_options: @llm_options,
            },
          ),
        )
      end

      def size = @blocks.size

      def enabled_size
        enabled_blocks.size
      end

      # Debug dump showing all blocks with their metadata.
      def debug_dump
        @blocks.map do |b|
          status = b.enabled? ? "" : " [DISABLED]"
          slot_info = b.slot ? " (#{b.slot})" : ""
          header = "[#{b.role}]#{slot_info}#{status}"
          meta_info = format_metadata(b)
          "#{header}#{meta_info}\n#{b.content}\n"
        end.join("\n")
      end

      private

      SQUASH_SYSTEM_EXCLUDE_SLOTS = %i[new_chat_prompt new_example_chat].freeze

      def squash_system_blocks(blocks)
        blocks = Array(blocks)

        squashed = []
        blocks.each do |block|
          next if block.role == :system && block.content.to_s.empty?

          should_squash = block.role == :system &&
            (block.name.nil? || block.name.to_s.empty?) &&
            (block.attachments.nil? || block.attachments.empty?) &&
            (block.message_metadata.nil? || block.message_metadata.empty?) &&
            !SQUASH_SYSTEM_EXCLUDE_SLOTS.include?(block.slot)
          last = squashed.last
          last_should_squash = last &&
            last.role == :system &&
            (last.name.nil? || last.name.to_s.empty?) &&
            (last.attachments.nil? || last.attachments.empty?) &&
            (last.message_metadata.nil? || last.message_metadata.empty?) &&
            !SQUASH_SYSTEM_EXCLUDE_SLOTS.include?(last.slot)

          if should_squash && last_should_squash
            merged_content = "#{last.content}\n#{block.content}"
            squashed[-1] = last.with(content: merged_content)
          else
            squashed << block
          end
        end

        squashed
      end

      def format_metadata(block)
        parts = []
        parts << "id=#{block.id[0, 8]}..." if block.id
        parts << "depth=#{block.depth}" if block.in_chat?
        parts << "order=#{block.order}" if block.order != 100
        parts << "priority=#{block.priority}" if block.priority != 100
        parts << "group=#{block.token_budget_group}" if block.token_budget_group != :default
        parts << "tags=#{block.tags.join(",")}" if block.tags.any?

        parts.empty? ? "" : " {#{parts.join(", ")}}"
      end

      def merge_in_chat_blocks_for_output(blocks)
        merged = []

        blocks.each do |block|
          if block.in_chat? && (prev = merged.last) &&
              prev.in_chat? &&
              prev.role == block.role &&
              prev.depth == block.depth &&
              prev.order == block.order &&
              (prev.attachments.nil? || prev.attachments.empty?) &&
              (block.attachments.nil? || block.attachments.empty?) &&
              (prev.message_metadata.nil? || prev.message_metadata.empty?) &&
              (block.message_metadata.nil? || block.message_metadata.empty?)
            merged_content = [prev.content.to_s.strip, block.content.to_s.strip].reject(&:empty?).join("\n")
            merged[-1] = prev.with(content: merged_content)
          else
            merged << block
          end
        end

        merged
      end

      def insert_at_index(index, block)
        unless block.is_a?(TavernKit::Prompt::Block)
          raise ArgumentError, "block must be a TavernKit::Prompt::Block"
        end

        new_blocks = blocks.dup
        new_blocks.insert(index, block)
        with_blocks(new_blocks)
      end
    end
  end
end
