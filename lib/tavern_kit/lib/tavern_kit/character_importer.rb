# frozen_string_literal: true

module TavernKit
  # Unified character import helper.
  #
  # Core handles CCv2/CCv3 sources (JSON/PNG wrappers). Platform layers may
  # register additional importers (e.g., platform-specific container formats).
  module CharacterImporter
    @importers_by_ext = {}

    class << self
      def register(ext, importer = nil, &block)
        handler = importer || block
        raise ArgumentError, "importer is required" unless handler

        @importers_by_ext[normalize_ext(ext)] = handler
      end

      def load(input)
        if input.is_a?(String) && File.file?(input)
          ext = File.extname(input).downcase
          importer = @importers_by_ext[ext]
          raise ArgumentError, "Unsupported character file type: #{ext.inspect}" unless importer

          return importer.call(input)
        end

        TavernKit::CharacterCard.load(input)
      end

      def importers
        @importers_by_ext.dup
      end

      private

      def normalize_ext(ext)
        e = ext.to_s.downcase
        e.start_with?(".") ? e : ".#{e}"
      end
    end
  end
end

# Built-in CC importers (Core).
TavernKit::CharacterImporter.register(".json") { |path| TavernKit::CharacterCard.load_file(path) }
TavernKit::CharacterImporter.register(".png") { |path| TavernKit::CharacterCard.load_file(path) }
TavernKit::CharacterImporter.register(".apng") { |path| TavernKit::CharacterCard.load_file(path) }

# ZIP-based containers (Core).
TavernKit::CharacterImporter.register(".byaf") do |path|
  hash = TavernKit::Archive::ByafParser.new(File.binread(path)).parse_character
  TavernKit::CharacterCard.load(hash)
end

TavernKit::CharacterImporter.register(".charx") { |path| TavernKit::Archive::CharX.load_character(path) }
