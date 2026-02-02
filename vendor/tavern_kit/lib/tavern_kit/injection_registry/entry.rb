# frozen_string_literal: true

module TavernKit
  module InjectionRegistry
    # A single registered injection entry.
    #
    # This is intentionally minimal and data-only. Layer-specific registries
    # (e.g. SillyTavern) can wrap/extend it as needed.
    Entry = Data.define(
      :id,
      :content,
      :position,
      :role,
      :depth,
      :scan,
      :ephemeral,
      :filter,
    ) do
      def initialize(
        id:,
        content:,
        position:,
        role: :system,
        depth: 4,
        scan: false,
        ephemeral: false,
        filter: nil
      )
        super(
          id: id.to_s,
          content: content.to_s,
          position: position&.to_sym,
          role: role&.to_sym || :system,
          depth: [depth.to_i, 0].max,
          scan: scan == true,
          ephemeral: ephemeral == true,
          filter: filter,
        )
      end

      def scan? = scan == true
      def ephemeral? = ephemeral == true
      def in_chat? = position == :chat

      def active_for?(ctx)
        return true unless filter.respond_to?(:call)

        !!filter.call(ctx)
      end
    end
  end
end
