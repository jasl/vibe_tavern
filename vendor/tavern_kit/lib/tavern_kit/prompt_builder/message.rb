# frozen_string_literal: true

require "date"

module TavernKit
  class PromptBuilder
    # Immutable message value object (Ruby 3.2+ Data class).
    #
    # @!attribute [r] role
    #   @return [Symbol] message role (:user, :assistant, :system, :tool, :function, ...)
    # @!attribute [r] content
    #   @return [String] message content
    # @!attribute [r] name
    #   @return [String, nil] optional speaker name (for scan buffer formatting)
    #
    # Additional optional metadata for ST-like session state:
    # - swipes: Array of alternative assistant message variants
    # - swipe_id: 0-based index of the currently selected swipe
    # - send_date: message timestamp
    #
    # Forward-compat fields:
    # - attachments: multimodal payloads (images/audio/video), provider-agnostic
    # - metadata: passthrough fields for dialect/tooling (tool calls, cache hints, etc.)
    Message = Data.define(:role, :content, :name, :swipes, :swipe_id, :send_date, :attachments, :metadata) do
      # Keep validation minimal: platform layers and dialect converters may
      # introduce additional roles (e.g., :function for OpenAI/RisuAI).
      ROLES = %i[system user assistant tool function].freeze

      def initialize(role:, content:, name: nil, swipes: nil, swipe_id: nil, send_date: nil, attachments: nil, metadata: nil)
        unless role.is_a?(Symbol)
          raise ArgumentError, "role must be a Symbol, got: #{role.inspect}"
        end

        unless content.is_a?(String)
          raise ArgumentError, "content must be a String, got: #{content.class}"
        end

        if !name.nil? && !name.is_a?(String)
          raise ArgumentError, "name must be a String (or nil), got: #{name.class}"
        end

        if !swipes.nil?
          unless swipes.is_a?(Array) && swipes.all? { |s| s.is_a?(String) }
            raise ArgumentError, "swipes must be an Array<String> (or nil)"
          end
        end

        if !swipe_id.nil? && !swipe_id.is_a?(Integer)
          raise ArgumentError, "swipe_id must be an Integer (or nil), got: #{swipe_id.class}"
        end

        if !send_date.nil? && !send_date.is_a?(Time) && !send_date.is_a?(DateTime) && !send_date.is_a?(Date) &&
            !send_date.is_a?(Integer) && !send_date.is_a?(Float) && !send_date.is_a?(String)
          raise ArgumentError,
                "send_date must be a Time/DateTime/Date/Integer/Float/String (or nil), got: #{send_date.class}"
        end

        if !attachments.nil? && !attachments.is_a?(Array)
          raise ArgumentError, "attachments must be an Array (or nil), got: #{attachments.class}"
        end
        attachments = attachments&.dup&.freeze

        if !metadata.nil? && !metadata.is_a?(Hash)
          raise ArgumentError, "metadata must be a Hash (or nil), got: #{metadata.class}"
        end
        metadata = metadata&.dup&.freeze

        super(
          role: role,
          content: content,
          name: name,
          swipes: swipes,
          swipe_id: swipe_id,
          send_date: send_date,
          attachments: attachments,
          metadata: metadata,
        )
      end

      # Convert to hash for API requests (minimal, only role/content/name).
      #
      # @return [Hash] minimal hash representation
      def to_h
        h = { role: role, content: content }
        h[:name] = name if name && !name.empty?
        h
      end

      # Convert to hash for serialization (includes all fields).
      #
      # @return [Hash] complete hash representation for persistence
      def to_serializable_hash
        h = { role: role.to_s, content: content }
        h[:name] = name if name
        h[:swipes] = swipes if swipes
        h[:swipe_id] = swipe_id if swipe_id
        h[:send_date] = serialize_send_date(send_date) if send_date
        h[:attachments] = attachments if attachments
        h[:metadata] = metadata if metadata
        h
      end

      private

      def serialize_send_date(date)
        case date
        when Time, DateTime
          date.iso8601
        when Date
          date.to_s
        else
          date
        end
      end
    end
  end
end
