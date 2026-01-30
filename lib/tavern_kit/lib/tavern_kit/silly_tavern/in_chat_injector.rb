# frozen_string_literal: true

module TavernKit
  module SillyTavern
    # Implements ST in-chat injection semantics.
    #
    # References:
    # - Text-completion pipeline: `doChatInject()` (public/script.js)
    # - Chat-completion pipeline: `populationInjectionPrompts()` (public/scripts/openai.js)
    #
    # This helper is used by the Wave 4 Injection middleware, but is kept as a
    # standalone unit so its contract can be tested directly.
    module InChatInjector
      module_function

      ROLE_ORDER = %i[system user assistant].freeze

      # @param messages [Array<Prompt::Message>] chronological (oldest -> newest)
      # @param entries [Array<InjectionRegistry::Entry>] in-chat entries only
      # @param generation_type [Symbol] :normal, :continue, ...
      # @param prompt_entries [Array<Prompt::PromptEntry>] optional Prompt Manager in-chat entries
      # @param continue_depth0_shift [Boolean] ST doChatInject() shifts depth=0 injections to depth=1 on continue
      # @return [Array<Prompt::Message>] new message array with injections applied
      def inject(messages, entries, generation_type:, prompt_entries: [], continue_depth0_shift: true)
        base = Array(messages)
        injects = Array(entries).select(&:in_chat?)

        prompts = Array(prompt_entries).select { |e| e.respond_to?(:in_chat?) && e.in_chat? }
        return base if injects.empty? && prompts.empty?

        # Mirror ST: reverse, splice, reverse back.
        buf = base.reverse
        total_inserted = 0

        max_depth = [injects.map(&:depth).max.to_i, prompts.map(&:depth).max.to_i].max

        (0..max_depth).each do |depth|
          role_messages = build_role_messages(prompts, injects, depth: depth)
          next if role_messages.empty?

          shift = continue_depth0_shift == true && generation_type.to_sym == :continue && depth == 0
          effective_depth = shift ? 1 : depth
          inject_idx = [effective_depth + total_inserted, buf.length].min

          buf.insert(inject_idx, *role_messages)
          total_inserted += role_messages.length
        end

        buf.reverse
      end

      def build_role_messages(prompt_entries, injects, depth:)
        # In ST chat-completions, Prompt Manager in-chat entries are grouped by
        # injection_order (default 100) and then roles are emitted per group.
        #
        # Due to the reverse/splice/reverse trick, iterating order groups from
        # high->low results in final chronological output sorted low->high.
        depth_prompts = prompt_entries.select { |p| p.depth == depth && p.content.to_s.strip.length.positive? }

        # Always create the default order bucket so extension prompts can still
        # inject even when Prompt Manager has no in-chat entries.
        order_groups = { 100 => [] }
        depth_prompts.each do |prompt|
          order = prompt.order.to_i
          order_groups[order] ||= []
          order_groups[order] << prompt
        end

        extension_by_role = build_extension_prompts(injects, depth: depth)

        out = []
        order_groups.keys.sort.reverse_each do |order|
          group = order_groups.fetch(order)

          ROLE_ORDER.each do |role|
            role_prompts = group.select { |p| p.role == role }.map { |p| p.content.to_s }.join("\n")
            extension_prompt = order == 100 ? extension_by_role.fetch(role, "") : ""

            joint = [role_prompts, extension_prompt].map { |s| s.to_s.strip }.reject(&:empty?).join("\n")
            next if joint.empty?

            out << TavernKit::Prompt::Message.new(role: role, content: joint)
          end
        end

        out
      end

      def build_extension_prompts(injects, depth:)
        by_role = {}

        ROLE_ORDER.each do |role|
          grouped = injects.select { |e| e.depth == depth && e.role == role }
          next if grouped.empty?

          content = grouped
            .sort_by(&:id)
            .map { |e| e.content.to_s.strip }
            .reject(&:empty?)
            .join("\n")

          by_role[role] = content unless content.empty?
        end

        by_role
      end
    end
  end
end
