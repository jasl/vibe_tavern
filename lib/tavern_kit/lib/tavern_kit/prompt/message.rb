# frozen_string_literal: true

require "date"

module TavernKit
  module Prompt
    # Immutable message value object (Ruby 3.2+ Data class).
    #
    # @!attribute [r] role
    #   @return [Symbol] message role (:user, :assistant, :system)
    # @!attribute [r] content
    #   @return [String] message content
    # @!attribute [r] name
    #   @return [String, nil] optional speaker name (for scan buffer formatting)
    #
    # Additional optional metadata for ST-like session state:
    # - swipes: Array of alternative assistant message variants
    # - swipe_id: 0-based index of the currently selected swipe
    # - send_date: message timestamp
    Message = Data.define(:role, :content, :name, :swipes, :swipe_id, :send_date) do
      # Valid roles for messages (aligned with chat completion APIs)
      ROLES = %i[system user assistant].freeze

      def initialize(role:, content:, name: nil, swipes: nil, swipe_id: nil, send_date: nil)
        unless role.is_a?(Symbol) && ROLES.include?(role)
          raise ArgumentError, "role must be one of #{ROLES.inspect}, got: #{role.inspect}"
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

        super(role: role, content: content, name: name, swipes: swipes, swipe_id: swipe_id, send_date: send_date)
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
