# frozen_string_literal: true

require "json"

require_relative "zip_reader"

module TavernKit
  module Archive
    # CHARX (.charx) importer (CCv3 ZIP container).
    #
    # Spec: resources/character-card-spec-v3/SPEC_V3.md
    #
    # TavernKit only extracts `card.json` (CCv3 payload). Assets are left to
    # the application layer; this helper exposes embedded asset paths so apps
    # can persist them if needed.
    class CharX
      CARD_PATH = "card.json"

      def self.open(source, **zip_limits)
        raise ArgumentError, "block is required" unless block_given?

        ZipReader.open(source, **zip_limits) do |zip|
          card_hash = zip.read_json(CARD_PATH)
          instance = new(zip: zip, card_hash: card_hash)
          yield instance
        end
      rescue TavernKit::Archive::ZipError => e
        raise TavernKit::Archive::CharXParseError, "Invalid CHARX file: #{e.message}"
      end

      def self.load_character(source, **zip_limits)
        character = nil
        open(source, **zip_limits) { |pkg| character = pkg.character }
        character
      end

      def initialize(zip:, card_hash:)
        @zip = zip
        @card_hash = card_hash

        unless @card_hash.is_a?(Hash)
          raise TavernKit::Archive::CharXParseError, "Invalid CHARX file: card.json must be a JSON object"
        end

        version = TavernKit::CharacterCard.detect_version(@card_hash)
        return if version == :v3

        raise TavernKit::Archive::CharXParseError, "Invalid CHARX file: card.json is not a Character Card V3 payload"
      end

      attr_reader :card_hash

      def character
        TavernKit::CharacterCard.load(card_hash)
      rescue TavernKit::InvalidCardError, TavernKit::UnsupportedVersionError => e
        raise TavernKit::Archive::CharXParseError, "Invalid CHARX card.json: #{e.message}"
      end

      # Return all file entry paths excluding `card.json`.
      #
      # Note: this includes application-specific files; use #embedded_asset_paths
      # to get only assets referenced by the CCv3 `assets[]` list.
      def entry_paths
        @zip.entries.reject { |p| p == CARD_PATH || p.end_with?("/") }
      end

      def embedded_asset_paths
        Array(card_hash.dig("data", "assets")).filter_map do |asset|
          next nil unless asset.is_a?(Hash)

          uri = asset["uri"].to_s
          next nil unless uri.start_with?("embeded://")

          uri.delete_prefix("embeded://")
        end.uniq
      end

      def read_asset(path, max_bytes: nil)
        @zip.read(path, max_bytes: max_bytes || ZipReader::DEFAULT_MAX_ENTRY_BYTES)
      end
    end
  end
end
