# frozen_string_literal: true

require "securerandom"
require_relative "message"

module TavernKit
  class PromptBuilder
    # A Block represents a single unit in a prompt plan.
    #
    # Blocks are the output of the prompt building process. They contain:
    # - The message content and role for LLM consumption
    # - Metadata for debugging, filtering, and budget management
    # - Positioning information for insertion logic
    class Block
      ROLES = %i[system user assistant tool function].freeze

      INSERTION_POINTS = %i[
        relative
        in_chat
        before_char_defs
        after_char_defs
        before_example_messages
        after_example_messages
        top_of_an
        bottom_of_an
        outlet
      ].freeze

      BUDGET_GROUPS = %i[system examples lore history custom default].freeze

      attr_reader :id,
                  :role,
                  :content,
                  :name,
                  :attachments,
                  :message_metadata,
                  :slot,
                  :enabled,
                  :removable,
                  :insertion_point,
                  :depth,
                  :order,
                  :priority,
                  :token_budget_group,
                  :tags,
                  :metadata

      def initialize(
        role:,
        content:,
        id: nil,
        name: nil,
        attachments: nil,
        message_metadata: nil,
        slot: nil,
        enabled: true,
        removable: true,
        insertion_point: :relative,
        depth: 0,
        order: 100,
        priority: 100,
        token_budget_group: :default,
        tags: [],
        metadata: {}
      )
        resolved_id = id || SecureRandom.uuid
        unless resolved_id.is_a?(String)
          raise ArgumentError, "id must be a String (or nil), got: #{resolved_id.class}"
        end
        @id = resolved_id

        unless role.is_a?(Symbol)
          raise ArgumentError, "role must be a Symbol, got: #{role.inspect}"
        end
        @role = role

        unless content.is_a?(String)
          raise ArgumentError, "content must be a String, got: #{content.class}"
        end
        @content = content

        if !name.nil? && !name.is_a?(String)
          raise ArgumentError, "name must be a String (or nil), got: #{name.class}"
        end
        @name = name

        if !attachments.nil? && !attachments.is_a?(Array)
          raise ArgumentError, "attachments must be an Array (or nil), got: #{attachments.class}"
        end
        @attachments = attachments&.dup&.freeze

        if !message_metadata.nil? && !message_metadata.is_a?(Hash)
          raise ArgumentError, "message_metadata must be a Hash (or nil), got: #{message_metadata.class}"
        end
        @message_metadata = message_metadata&.dup&.freeze

        if !slot.nil? && !slot.is_a?(Symbol)
          raise ArgumentError, "slot must be a Symbol (or nil), got: #{slot.class}"
        end
        @slot = slot

        unless enabled == true || enabled == false
          raise ArgumentError, "enabled must be a Boolean, got: #{enabled.class}"
        end
        @enabled = enabled

        unless removable == true || removable == false
          raise ArgumentError, "removable must be a Boolean, got: #{removable.class}"
        end
        @removable = removable

        unless insertion_point.is_a?(Symbol)
          raise ArgumentError, "insertion_point must be a Symbol, got: #{insertion_point.inspect}"
        end
        @insertion_point = insertion_point

        unless depth.is_a?(Integer) && depth >= 0
          raise ArgumentError, "depth must be a non-negative Integer, got: #{depth.inspect}"
        end
        @depth = depth

        unless order.is_a?(Integer)
          raise ArgumentError, "order must be an Integer, got: #{order.class}"
        end
        @order = order

        unless priority.is_a?(Integer)
          raise ArgumentError, "priority must be an Integer, got: #{priority.class}"
        end
        @priority = priority

        unless token_budget_group.is_a?(Symbol)
          raise ArgumentError, "token_budget_group must be a Symbol, got: #{token_budget_group.inspect}"
        end
        @token_budget_group = token_budget_group

        unless tags.is_a?(Array) && tags.all? { |t| t.is_a?(Symbol) }
          raise ArgumentError, "tags must be an Array<Symbol>, got: #{tags.class}"
        end
        @tags = tags.dup.freeze

        unless metadata.is_a?(Hash)
          raise ArgumentError, "metadata must be a Hash, got: #{metadata.class}"
        end
        @metadata = metadata.dup.freeze

        freeze
      end

      def enabled? = @enabled
      def disabled? = !@enabled
      def removable? = @removable
      def in_chat? = @insertion_point == :in_chat
      def relative? = @insertion_point == :relative

      # Convert to a Message for LLM consumption.
      # @return [Message]
      def to_message
        Message.new(role: role, content: content, name: name, attachments: attachments, metadata: message_metadata)
      end

      # Serialize to a hash for debugging/inspection.
      # @return [Hash]
      def to_h
        {
          id: id,
          role: role,
          content: content,
          name: name,
          attachments: attachments,
          message_metadata: message_metadata,
          slot: slot,
          enabled: enabled,
          removable: removable,
          insertion_point: insertion_point,
          depth: depth,
          order: order,
          priority: priority,
          token_budget_group: token_budget_group,
          tags: tags,
          metadata: metadata,
        }
      end

      # Create a new Block with modified attributes.
      # @param attrs [Hash] attributes to override
      # @return [Block] new block with merged attributes
      def with(**attrs)
        Block.new(**to_h.merge(attrs))
      end

      def disable = with(enabled: false)
      def enable = with(enabled: true)
    end
  end
end
