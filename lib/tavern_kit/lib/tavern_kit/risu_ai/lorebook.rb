# frozen_string_literal: true

require_relative "../regex_safety"

module TavernKit
  module RisuAI
    module Lorebook
      Result = Data.define(:prompts)

      module_function

      # Minimal matcher for RisuAI lorebook entries (Wave 5c kickoff).
      #
      # This mirrors the upstream matching approach:
      # - scan last N messages (scan_depth)
      # - case-insensitive search
      # - "full word" mode matches exact tokens split on spaces
      # - "partial" mode removes spaces from both message and key
      # - regex mode expects JS-style /pattern/flags strings
      #
      # NOTE: This intentionally accepts Hash lore entries to match RisuAI's
      # internal JSON-y shape; higher-level conversion to Core Lore::Entry will
      # be handled by the Wave 5c engine.
      def match(messages, lores, full_word_matching: false, scan_depth: 50, recursive_scanning: false)
        scan_depth = scan_depth.to_i
        scan_depth = 0 if scan_depth.negative?

        scan_messages = Array(messages).last(scan_depth)
        items = Array(lores)

        actives = []

        items.each do |raw|
          h = TavernKit::Utils.deep_stringify_keys(raw.is_a?(Hash) ? raw : {})

          content = h.fetch("content", "").to_s
          key = h.fetch("key", "").to_s
          secondkey = h.fetch("secondkey", "").to_s

          always_active = TavernKit::Coerce.bool(h["alwaysActive"], default: false)
          selective = TavernKit::Coerce.bool(h["selective"], default: false)
          use_regex = TavernKit::Coerce.bool(h["useRegex"], default: false)

          insertion_order = Integer(h["insertorder"] || 0) rescue 0

          primary_keys = split_keys(key)
          secondary_keys = split_keys(secondkey)

          next if !always_active && primary_keys.empty?

          activated =
            if always_active
              true
            else
              search_match?(scan_messages, primary_keys, regex: use_regex, full_word_matching: full_word_matching) &&
                (!selective || secondary_keys.empty? || search_match?(scan_messages, secondary_keys, regex: use_regex, full_word_matching: full_word_matching))
            end

          next unless activated

          actives << [insertion_order, strip_decorators(content)]
        end

        prompts = actives.sort_by { |order, _| -order }.map { |_, prompt| prompt }
        Result.new(prompts: prompts)
      end

      def split_keys(value)
        value.to_s.split(",").map(&:strip).reject(&:empty?)
      end

      def search_match?(messages, keys, regex:, full_word_matching:)
        return false if keys.empty?

        if regex
          return false if keys.any? { |k| !k.start_with?("/") }

          keys.any? do |regex_string|
            re = parse_js_regex(regex_string)
            next false unless re

            messages.any? do |m|
              text = extract_message_data(m)
              TavernKit::RegexSafety.match?(re, text)
            end
          end
        elsif full_word_matching
          keys2 = keys.map { |k| k.downcase }
          messages.any? do |m|
            text = extract_message_data(m).downcase
            words = text.split(" ")
            keys2.any? { |k| words.include?(k) }
          end
        else
          keys2 = keys.map { |k| k.downcase.delete(" ") }
          messages.any? do |m|
            text = extract_message_data(m).downcase.delete(" ")
            keys2.any? { |k| text.include?(k) }
          end
        end
      end

      def extract_message_data(value)
        return value.to_s unless value.is_a?(Hash)

        v = value["data"]
        v = value[:data] if v.nil?
        v.to_s
      end

      def parse_js_regex(str)
        s = str.to_s
        return nil unless s.start_with?("/")

        last = s.rindex("/")
        return nil if last.nil? || last == 0

        pattern = s[1...last]
        flags = s[(last + 1)..].to_s

        options = 0
        options |= Regexp::IGNORECASE if flags.include?("i")
        options |= Regexp::MULTILINE if flags.include?("m") || flags.include?("s")

        TavernKit::RegexSafety.compile(pattern, options: options)
      end

      def strip_decorators(content)
        TavernKit::RisuAI::Lore::DecoratorParser.parse(content).content.to_s
      end
    end
  end
end
