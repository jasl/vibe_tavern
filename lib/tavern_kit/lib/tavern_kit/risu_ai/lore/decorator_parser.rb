# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Lore
      # Parser for RisuAI inline decorators.
      #
      # RisuAI uses CCardLib's decorator parser, which scans only the leading
      # `@@...` (and conditional `@@@...`) lines of a prompt. Parsing stops at the
      # first non-decorator line, returning the remaining content.
      #
      # Upstream reference:
      # resources/Risuai/node_modules/@risuai/ccardlib/dist/index.js (decorator.parse)
      class DecoratorParser
        ParseResult = Data.define(:content, :names)

        # Parse and strip leading decorators.
        #
        # @yield [name, args] when a decorator is encountered
        # @yieldparam name [String]
        # @yieldparam args [Array<String>]
        # @yieldreturn [Boolean, nil] return `false` to mark the decorator as
        #   "not applied" and enable parsing of subsequent `@@@...` fallback lines.
        #
        # @return [ParseResult]
        def self.parse(text)
          lines = text.to_s.strip.split("\n")

          names = []
          conditional_enabled = false

          lines.each_with_index do |raw_line, idx|
            line = raw_line.to_s.strip
            line = "@@end" if line == "@@@end"

            unless line.start_with?("@@")
              remaining = lines[idx..].join("\n").strip
              return ParseResult.new(content: remaining, names: names.freeze)
            end

            # Conditional decorators (`@@@...`) are only active when the previous
            # decorator returned false.
            if line.start_with?("@@@") && !conditional_enabled
              next
            end

            space_idx = line.index(" ")
            space_idx = line.length if space_idx.nil?

            prefix_len = line.start_with?("@@@") ? 3 : 2
            name = line[prefix_len...space_idx]
            args = line.slice(space_idx..).to_s.split(",").map(&:strip).reject(&:empty?)

            if name.to_s.empty?
              conditional_enabled = false
              next
            end

            names << name

            applied = block_given? ? yield(name, args) : nil
            conditional_enabled = (applied == false)
          end

          ParseResult.new(content: "", names: names.freeze)
        end
      end
    end
  end
end
