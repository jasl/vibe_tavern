# frozen_string_literal: true

module TavernKit
  module SillyTavern
    # Implements ST in-chat injection semantics (script.js#doChatInject).
    #
    # This helper is used by the Wave 4 Injection middleware, but is kept as a
    # standalone unit so its contract can be tested directly.
    module InChatInjector
      module_function

      ROLE_ORDER = %i[system user assistant].freeze

      # @param messages [Array<Prompt::Message>] chronological (oldest -> newest)
      # @param entries [Array<InjectionRegistry::Entry>] in-chat entries only
      # @param generation_type [Symbol] :normal, :continue, ...
      # @return [Array<Prompt::Message>] new message array with injections applied
      def inject(messages, entries, generation_type:)
        base = Array(messages)
        injects = Array(entries).select(&:in_chat?)
        return base if injects.empty?

        # Mirror ST: reverse, splice, reverse back.
        buf = base.reverse
        total_inserted = 0

        max_depth = injects.map(&:depth).max.to_i

        (0..max_depth).each do |depth|
          role_messages = build_role_messages(injects, depth: depth)
          next if role_messages.empty?

          effective_depth = (generation_type.to_sym == :continue && depth == 0) ? 1 : depth
          inject_idx = [effective_depth + total_inserted, buf.length].min

          buf.insert(inject_idx, *role_messages)
          total_inserted += role_messages.length
        end

        buf.reverse
      end

      def build_role_messages(injects, depth:)
        out = []

        ROLE_ORDER.each do |role|
          grouped = injects.select { |e| e.depth == depth && e.role == role }
          next if grouped.empty?

          content = grouped
            .sort_by(&:id)
            .map { |e| e.content.to_s.strip }
            .reject(&:empty?)
            .join("\n")

          next if content.empty?

          out << TavernKit::Prompt::Message.new(role: role, content: content)
        end

        out
      end
    end
  end
end
