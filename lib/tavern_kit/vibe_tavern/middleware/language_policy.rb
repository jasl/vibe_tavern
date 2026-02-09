# frozen_string_literal: true

require_relative "../output_tags/sanitizers/lang_spans"

module TavernKit
  module VibeTavern
    module Middleware
      # Stage: inject a short "output language" policy block.
      #
      # Contract (P0):
      # - Constrain human-facing assistant text to a target language
      # - Preserve "verbatim zones" (code/protocol/macros) by prompt policy
      # - Never introduce app-level safety/ethics policy text
      #
      # Configuration:
      # - runtime[:language_policy] (strict)
      class LanguagePolicy < TavernKit::Prompt::Middleware::Base
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

        SUPPORTED_TARGET_LANGS = %w[
          en-US
          zh-CN
          zh-TW
          ko-KR
          ja-JP
          yue-HK
        ].freeze

        CANONICAL_TARGET_LANGS = {
          "en" => "en-US",
          "en-us" => "en-US",
          "zh-cn" => "zh-CN",
          "zh-tw" => "zh-TW",
          "zh-hans" => "zh-CN",
          "zh-hans-cn" => "zh-CN",
          "zh-hant" => "zh-TW",
          "zh-hant-tw" => "zh-TW",
          "ko-kr" => "ko-KR",
          "ko" => "ko-KR",
          "ja-jp" => "ja-JP",
          "ja" => "ja-JP",
          "yue-hk" => "yue-HK",
          "yue" => "yue-HK",
        }.freeze

        private

        def before(ctx)
          cfg = language_policy_config(ctx)
          return unless cfg

          enabled = TavernKit::Coerce.bool(cfg.fetch(:enabled), default: false)
          return unless enabled

          raw_target = cfg.fetch(:target_lang)
          raise ArgumentError, "language_policy.target_lang must be present" if raw_target.to_s.strip.empty?

          target_lang = canonicalize_target_lang(raw_target)
          unless SUPPORTED_TARGET_LANGS.include?(target_lang)
            ctx.warn("language_policy.target_lang not supported (disabling): #{raw_target.inspect}")
            return
          end

          style_hint = cfg.fetch(:style_hint, nil)
          style_hint = style_hint.to_s.strip
          style_hint = nil if style_hint.empty?
          special_tags =
            Array(cfg.fetch(:special_tags, nil))
              .map { |item| item.to_s.strip }
              .reject(&:empty?)
              .uniq

          policy_text_builder = cfg.fetch(:policy_text_builder, nil)
          policy_text_builder ||= option(:policy_text_builder)

          policy_text =
            build_policy_text(
              ctx,
              target_lang,
              style_hint: style_hint,
              special_tags: special_tags,
              policy_text_builder: policy_text_builder,
            )
          return if policy_text.strip.empty?

          insert_policy_block!(ctx, target_lang, policy_text)
        end

        def language_policy_config(ctx)
          runtime = ctx.runtime
          raw = runtime&.[](:language_policy)
          return nil if raw.nil?

          raise ArgumentError, "runtime[:language_policy] must be a Hash" unless raw.is_a?(Hash)

          raw
        end

        def canonicalize_target_lang(raw)
          s = raw.to_s.strip.tr("_", "-")
          return "" if s.empty?

          CANONICAL_TARGET_LANGS.fetch(s.downcase, s)
        end

        def build_policy_text(ctx, target_lang, style_hint:, special_tags:, policy_text_builder:)
          builder = policy_text_builder || DEFAULT_POLICY_TEXT_BUILDER
          raise ArgumentError, "language_policy.policy_text_builder must respond to #call" unless builder.respond_to?(:call)

          builder.call(target_lang, style_hint: style_hint, special_tags: special_tags).to_s
        end

        def insert_policy_block!(ctx, target_lang, policy_text)
          ctx.blocks = Array(ctx.blocks).dup

          policy_block =
            TavernKit::Prompt::Block.new(
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

          ctx.plan =
            TavernKit::Prompt::Plan.new(
              blocks: ctx.blocks,
              outlets: plan.outlets,
              lore_result: plan.lore_result,
              trim_report: plan.trim_report,
              greeting: plan.greeting,
              greeting_index: plan.greeting_index,
              warnings: ctx.warnings,
              trace: plan.trace,
              llm_options: plan.llm_options,
            )
        end
      end
    end
  end
end

TavernKit.on_load(:vibe_tavern, id: :"vibe_tavern.language_policy.lang_spans") do |infra|
  registry = infra.output_tags_registry
  registry.register_sanitizer(:lang_spans, TavernKit::VibeTavern::OutputTags::Sanitizers::LangSpans)
end
