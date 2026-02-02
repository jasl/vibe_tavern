# frozen_string_literal: true

module TavernKit
  module SillyTavern
    # Small helper for Stage 5 Injection that keeps "schedule + rewrite" rules testable.
    module InjectionPlanner
      module_function

      PERSONA_POSITIONS = %i[in_prompt top_an bottom_an at_depth none].freeze

      # Determine whether Author's Note should be injected for this turn.
      #
      # Contract: `turn_count` is the number of user messages in the chat,
      # including the current user input (app-owned).
      def authors_note_scheduled?(turn_count:, frequency:)
        interval = frequency.to_i
        return false if interval <= 0

        turns = turn_count.to_i
        turns > 0 && (turns % interval).zero?
      end

      # Build an Author's Note injection entry (or nil when not injected).
      #
      # Persona TOP/BOTTOM is applied by rewriting the note content only when
      # the note is scheduled to inject (ST parity).
      def authors_note_entry(
        turn_count:,
        text:,
        frequency:,
        position:,
        depth:,
        role:,
        allow_wi_scan: false,
        overrides: nil,
        persona_text: nil,
        persona_position: :none
      )
        return nil unless authors_note_scheduled?(turn_count: turn_count, frequency: frequency)

        content = text.to_s.strip
        return nil if content.empty?

        persona_pos = normalize_persona_position(persona_position)
        if persona_pos == :top_an || persona_pos == :bottom_an
          persona = persona_text.to_s.strip
          if !persona.empty?
            content = persona_pos == :top_an ? "#{persona}\n#{content}" : "#{content}\n#{persona}"
          end
        end

        return nil if content.strip.empty?

        cfg = Utils::HashAccessor.wrap(overrides || {})

        resolved_position = cfg.fetch(:position, default: position)
        resolved_depth = cfg.fetch(:depth, default: depth)
        resolved_role = cfg.fetch(:role, default: role)

        TavernKit::InjectionRegistry::Entry.new(
          id: "authors_note",
          content: content,
          position: map_authors_note_position(resolved_position),
          depth: Integer(resolved_depth || 0),
          role: Coerce.role(resolved_role, default: :system),
          scan: allow_wi_scan == true,
          ephemeral: false,
          filter: nil,
        )
      end

      # Build a persona in-chat injection entry for AT_DEPTH position.
      #
      # NOTE: TOP/BOTTOM positions are handled by rewriting Author's Note.
      def persona_at_depth_entry(text:, position:, depth:, role:)
        pos = normalize_persona_position(position)
        return nil unless pos == :at_depth

        content = text.to_s.strip
        return nil if content.empty?

        TavernKit::InjectionRegistry::Entry.new(
          id: "persona_description",
          content: content,
          position: :chat,
          depth: Integer(depth || 0),
          role: Coerce.role(role, default: :system),
          scan: true, # ST parity: allowWIScan=true for AT_DEPTH persona injections.
          ephemeral: false,
          filter: nil,
        )
      end

      def normalize_persona_position(value)
        sym = value.to_s.strip.downcase.to_sym
        PERSONA_POSITIONS.include?(sym) ? sym : :none
      end

      def map_authors_note_position(value)
        raw = value.to_s.strip.downcase
        case raw
        when "none" then :none
        when "before_prompt", "before" then :before
        when "in_prompt", "after", "prompt" then :after
        when "in_chat", "chat" then :chat
        else
          :chat
        end
      end
    end
  end
end
