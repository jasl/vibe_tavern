# frozen_string_literal: true

module AgentCore
  module Contrib
    module LanguagePolicyPrompt
      module_function

      def build(target_lang, style_hint: nil, special_tags: [], tool_calls_rule: true)
        lang = target_lang.to_s.strip
        raise ArgumentError, "target_lang is required" if lang.empty?

        hint = style_hint.to_s.strip
        hint = nil if hint.empty?

        tags =
          Array(special_tags)
            .map { |t| t.to_s.strip }
            .reject(&:empty?)
            .uniq

        parts = []
        parts << "Language Policy:"

        lang_line = "- Respond in: #{lang} (natural, idiomatic)."
        lang_line = "#{lang_line} Style: #{hint}." if hint
        parts << lang_line

        parts << "- Preserve verbatim: code blocks (```), inline code (`), Liquid ({{ }}, {% %}), HTML/XML tags (<...>), URLs/Markdown links (do not rewrite or shorten)."
        parts << "- Machine-readable output: keep tool names, directive types, and JSON keys unchanged; output JSON only when required."
        parts << "- Tool calls: emit tool calls only; no natural-language content." if tool_calls_rule

        if tags.any?
          parts << "- Special tags: preserve content inside <tag>...</tag> for: #{tags.join(", ")}."
        end

        if tags.any? { |tag| tag.downcase == "lang" }
          parts << "- Mixed-language spans: use <lang code=\"...\">...</lang>. Inside must be in that language; outside stays #{lang}."
        end

        parts.join("\n")
      end
    end
  end
end
