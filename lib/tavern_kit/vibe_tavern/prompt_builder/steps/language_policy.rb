# frozen_string_literal: true

require_relative "../../language_policy"

module TavernKit
  module VibeTavern
    module PromptBuilder
      module Steps
        # Stage: inject a short "output language" policy block.
        #
        # Contract (P0):
        # - Constrain human-facing assistant text to a target language
        # - Preserve "verbatim zones" (code/protocol/macros) by prompt policy
        # - Never introduce app-level safety/ethics policy text
        #
        # Configuration:
        # - typed `LanguagePolicy::Config` injected via step options
        class LanguagePolicy < TavernKit::PromptBuilder::Step
          DEFAULT_POLICY_TEXT_BUILDER =
            lambda do |target_lang, style_hint:, special_tags:|
              parts = []
              parts << "Language Policy:"

              lang_line = "- Respond in: #{target_lang} (natural, idiomatic)."
              lang_line = "#{lang_line} Style: #{style_hint}." if style_hint
              parts << lang_line

              parts << "- Preserve verbatim: code blocks (```), inline code (`), Liquid ({{ }}, {% %}), HTML/XML tags (<...>), URLs/Markdown links (do not rewrite or shorten)."
              parts << "- Machine-readable output: keep tool names, directive types, and JSON keys unchanged; output JSON only when required."
              parts << "- Tool calls: emit tool calls only; no natural-language content."

              if special_tags.any?
                parts << "- Special tags: preserve content inside <tag>...</tag> for: #{special_tags.join(", ")}."
              end

              if special_tags.any? { |tag| tag.to_s.strip.downcase == "lang" }
                parts << "- Mixed-language spans: use <lang code=\"...\">...</lang>. Inside must be in that language; outside stays #{target_lang}."
              end

              parts.join("\n")
            end.freeze

        private

        def before(ctx)
          cfg = option(:config)
          return if cfg.nil?
          raise ArgumentError, "language_policy step config must be LanguagePolicy::Config" unless cfg.is_a?(TavernKit::VibeTavern::LanguagePolicy::Config)
          return unless cfg.enabled

          target_lang = cfg.target_lang.to_s.strip
          raise ArgumentError, "language_policy.target_lang must be present" if target_lang.empty?

          unless TavernKit::VibeTavern::LanguagePolicy::SUPPORTED_TARGET_LANGS.include?(target_lang)
            ctx.warn("language_policy.target_lang not supported (disabling): #{target_lang.inspect}")
            return
          end

          style_hint = cfg.style_hint
          special_tags = cfg.special_tags
          policy_text_builder = cfg.policy_text_builder || option(:policy_text_builder)

          policy_text =
            build_policy_text(
              target_lang,
              style_hint: style_hint,
              special_tags: special_tags,
              policy_text_builder: policy_text_builder,
            )
          return if policy_text.strip.empty?

          insert_policy_block!(ctx, target_lang, policy_text)
        end

        def build_policy_text(target_lang, style_hint:, special_tags:, policy_text_builder:)
          builder = policy_text_builder || DEFAULT_POLICY_TEXT_BUILDER
          raise ArgumentError, "language_policy.policy_text_builder must respond to #call" unless builder.respond_to?(:call)

          builder.call(target_lang, style_hint: style_hint, special_tags: special_tags).to_s
        end

        def insert_policy_block!(ctx, target_lang, policy_text)
          ctx.blocks = Array(ctx.blocks).dup

          policy_block =
            TavernKit::PromptBuilder::Block.new(
              role: :system,
              content: policy_text,
              slot: :language_policy,
              token_budget_group: :system,
              metadata: { source: :language_policy, target_lang: target_lang },
            )

          insertion_index = resolve_insertion_index(ctx.blocks)
          ctx.blocks.insert(insertion_index, policy_block)

          rebuild_plan!(ctx)

          ctx.instrument(:stat, stage: :language_policy, key: :enabled, value: true) if ctx.instrumenter
        end

        def resolve_insertion_index(blocks)
          idx = blocks.find_index { |b| b.respond_to?(:slot) && b.slot == :user_message }
          return idx if idx

          # Prefer inserting just before the trailing "prompting" messages
          # (user/tool) so the last message remains user/tool for chat semantics.
          tail_start = blocks.length
          while tail_start.positive?
            b = blocks[tail_start - 1]
            role = b.respond_to?(:role) ? b.role : nil
            break unless role == :user || role == :tool

            tail_start -= 1
          end

          return tail_start if tail_start < blocks.length

          blocks.length
        end

        def rebuild_plan!(ctx)
          plan = ctx.plan
          return unless plan

          ctx.plan = plan.with_blocks(ctx.blocks).with(warnings: ctx.warnings)
        end
        end
      end
    end
  end
end
