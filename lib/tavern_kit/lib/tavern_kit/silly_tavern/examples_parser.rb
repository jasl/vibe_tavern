# frozen_string_literal: true

module TavernKit
  module SillyTavern
    # Parses and formats character example dialogue blocks using ST's `<START>`
    # marker semantics.
    #
    # This is used by macros like {{mesExamples}} and by prompt assembly for
    # text-completion formats.
    module ExamplesParser
      module_function

      START_MARKER = "<START>"

      # Parse example blocks.
      #
      # @param examples_str [String]
      # @param example_separator [String, nil] string inserted between blocks for non-openai chat formats
      # @param is_instruct [Boolean] when true, uses <START> headings regardless of main_api
      # @param main_api [String, Symbol, nil] when "openai", uses <START> headings
      # @return [Array<String>]
      def parse(examples_str, example_separator: nil, is_instruct: false, main_api: nil)
        raw = examples_str.to_s
        return [] if raw.empty? || raw == START_MARKER

        normalized = raw
        normalized = "#{START_MARKER}\n#{normalized.strip}" unless normalized.start_with?(START_MARKER)

        sep = example_separator.to_s
        heading =
          if main_api.to_s == "openai" || is_instruct == true
            "#{START_MARKER}\n"
          elsif sep.empty?
            ""
          else
            "#{sep}\n"
          end

        normalized
          .split(/<START>/i)
          .drop(1)
          .map { |block| "#{heading}#{block.strip}\n" }
      end

      def format(examples_str, **kwargs)
        parse(examples_str, **kwargs).join
      end
    end
  end
end
