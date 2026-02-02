# frozen_string_literal: true

module TavernKit
  module SillyTavern
    # In-memory registry for ST extension prompts (mirrors ST `extension_prompts`).
    #
    # This is the Ruby-side replacement for ST `/inject` and related extension
    # prompt features.
    class InjectionRegistry < TavernKit::InjectionRegistry::Base
      ST_POSITION_MAP = {
        -1 => :none,  # NONE
        0 => :after,  # IN_PROMPT (after main prompt)
        1 => :chat,   # IN_CHAT
        2 => :before, # BEFORE_PROMPT
      }.freeze

      ST_ROLE_MAP = { 0 => :system, 1 => :user, 2 => :assistant }.freeze

      def self.from_st_json(hash)
        reg = new
        Utils.deep_stringify_keys(hash).each do |id, attrs|
          next unless attrs.is_a?(Hash)

          reg.register(
            id: id,
            content: attrs["value"],
            position: attrs["position"],
            depth: attrs["depth"],
            scan: attrs["scan"],
            role: attrs["role"],
            filter: attrs["filter"],
          )
        end
        reg
      end

      def initialize
        @entries = {}
      end

      def register(id:, content:, position:, **opts)
        entry = TavernKit::InjectionRegistry::Entry.new(
          id: id,
          content: content,
          position: coerce_position(position),
          role: coerce_role(opts[:role]),
          depth: opts.fetch(:depth, 4),
          scan: opts.fetch(:scan, false),
          ephemeral: opts.fetch(:ephemeral, false),
          filter: coerce_filter(opts[:filter]),
        )

        @entries[entry.id] = entry
        entry
      end

      def remove(id:)
        @entries.delete(id.to_s)
      end

      def each(&block)
        entries = @entries.values.sort_by(&:id)
        return entries.each unless block

        entries.each(&block)
      end

      def ephemeral_ids
        each.select(&:ephemeral?).map(&:id)
      end

      private

      def coerce_position(value)
        return value.to_sym if value.is_a?(Symbol) && %i[before after chat none].include?(value)

        if value.is_a?(Integer)
          return ST_POSITION_MAP.fetch(value, :after)
        end

        raw = value.to_s.strip.downcase
        case raw
        when "", "after", "in_prompt", "inprompt", "prompt" then :after
        when "before", "before_prompt", "beforeprompt" then :before
        when "chat", "in_chat", "inchat" then :chat
        when "none" then :none
        when "-1" then :none
        when "0" then :after
        when "1" then :chat
        when "2" then :before
        else
          :after
        end
      end

      def coerce_role(value)
        return ST_ROLE_MAP.fetch(value, :system) if value.is_a?(Integer)
        return value.to_sym if value.is_a?(Symbol)

        Coerce.role(value, default: :system)
      end

      def coerce_filter(value)
        return nil if value.nil?

        if value.respond_to?(:call)
          # Treat filter failures as external input issues: warn + default active.
          return lambda do |ctx|
            begin
              !!value.call(ctx)
            rescue StandardError => e
              ctx.warn("InjectionRegistry filter error (treated as unfiltered): #{e.class}: #{e.message}") if ctx.respond_to?(:warn)
              true
            end
          end
        end

        # ST stores filter closures as JS source strings. We can't evaluate them
        # safely here, so treat as "unfiltered" with a warning (once per build).
        js = value.to_s
        lambda do |ctx|
          ctx.warn("Unsupported ST filter closure ignored: #{js.inspect}") if ctx.respond_to?(:warn)
          true
        end
      end
    end
  end
end
