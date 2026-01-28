# frozen_string_literal: true

module TavernKit
  # Unified module for loading and exporting Character Cards.
  #
  # Handles loading from multiple sources (PNG, JSON files, hashes) and
  # auto-detects V2/V3 format. Always returns a Character instance.
  #
  # Design principle: "strict in, strict out"
  # - Requires spec-compliant payloads (no legacy field fallbacks)
  # - Exports spec-compliant V2/V3 hashes
  #
  # @example Load from any source
  #   character = TavernKit::CharacterCard.load("card.png")
  #   character = TavernKit::CharacterCard.load("card.json")
  #   character = TavernKit::CharacterCard.load(hash)
  #
  # @example Export to specific version
  #   v2_hash = TavernKit::CharacterCard.export_v2(character)
  #   v3_hash = TavernKit::CharacterCard.export_v3(character)
  #
  # @example Write to PNG
  #   TavernKit::CharacterCard.write_to_png(
  #     character,
  #     input_png: "avatar.png",
  #     output_png: "character_card.png",
  #     format: :both
  #   )
  module CharacterCard
    # V3-only fields that don't exist in V2 spec
    V3_ONLY_FIELDS = %w[
      assets nickname creator_notes_multilingual source
      group_only_greetings creation_date modification_date
    ].freeze

    # Key for storing V3 fields when downgrading to V2
    V3_EXTRAS_KEY = "cc_extractor/v3"

    # Required fields for V1 detection
    V1_REQUIRED_FIELDS = %w[name description first_mes].freeze

    class << self
      # Load a Character from any supported source.
      #
      # Auto-detects the input type:
      # - String ending in .json: load as JSON file
      # - String ending in .png/.apng: load as PNG file
      # - Hash: parse directly
      # - Other string: try to parse as JSON
      #
      # @param input [String, Hash] file path, JSON string, or parsed hash
      # @return [Character] loaded character
      # @raise [InvalidCardError] if card format is unsupported
      # @raise [ArgumentError] if input type is not supported
      def load(input)
        hash = extract_hash(input)
        parse_hash(hash)
      end

      # Load a Character from a file path.
      #
      # @param path [String] .json, .png, or .apng file path
      # @return [Character]
      def load_file(path)
        ext = File.extname(path.to_s).downcase
        case ext
        when ".json"
          parse_hash(JSON.parse(File.read(path)))
        when ".png", ".apng"
          load_png(path)
        else
          raise ArgumentError, "Unsupported file type: #{ext.inspect}. Expected .json/.png/.apng."
        end
      end

      # Load a Character from a PNG/APNG file.
      #
      # @param path [String] .png/.apng file path
      # @return [Character]
      def load_png(path)
        parse_hash(TavernKit::Png::Parser.extract_card_payload(path))
      end

      # Load a Character from a parsed hash.
      #
      # @param hash [Hash] character card hash
      # @return [Character]
      def load_hash(hash)
        parse_hash(hash)
      end

      # Write a Character to a PNG file with embedded metadata.
      #
      # Creates tEXt chunks containing base64-encoded JSON character data.
      # Supports dual-write (both V2 and V3) for maximum compatibility.
      #
      # @param character [Character] the character to embed
      # @param input_png [String] path to source PNG file (avatar image)
      # @param output_png [String] path to write output PNG file
      # @param format [Symbol] :v2_only, :v3_only, or :both (default)
      # @return [void]
      # @raise [TavernKit::Png::WriteError] if writing fails
      # @raise [TavernKit::Png::ParseError] if input is not a valid PNG
      def write_to_png(character, input_png:, output_png:, format: :both)
        Png::Writer.embed_character(input_png, output_png, character, format: format)
      end

      # Export a Character to V2 format hash.
      #
      # @param character [Character] the character to export
      # @param preserve_v3_fields [Boolean] store V3-only fields in extensions
      # @return [Hash] V2-compliant hash suitable for JSON serialization
      def export_v2(character, preserve_v3_fields: true)
        data = character.data

        data_hash = {
          "name" => data.name,
          "description" => data.description || "",
          "personality" => data.personality || "",
          "scenario" => data.scenario || "",
          "first_mes" => data.first_mes || "",
          "mes_example" => data.mes_example || "",
          "creator_notes" => data.creator_notes || "",
          "system_prompt" => data.system_prompt || "",
          "post_history_instructions" => data.post_history_instructions || "",
          "alternate_greetings" => data.alternate_greetings || [],
          "tags" => data.tags || [],
          "creator" => data.creator || "",
          "character_version" => data.character_version || "",
          "extensions" => deep_copy(data.extensions || {}),
        }

        # Include character_book if present
        data_hash["character_book"] = deep_copy(data.character_book) if data.character_book

        # Preserve V3 fields in extensions if requested
        if preserve_v3_fields
          extras = extract_v3_extras(data)
          unless extras.empty?
            data_hash["extensions"][V3_EXTRAS_KEY] ||= {}
            extras.each { |k, v| data_hash["extensions"][V3_EXTRAS_KEY][k] ||= v }
          end
        end

        {
          "spec" => "chara_card_v2",
          "spec_version" => "2.0",
          "data" => data_hash,
        }
      end

      # Export a Character to V3 format hash.
      #
      # @param character [Character] the character to export
      # @return [Hash] V3-compliant hash suitable for JSON serialization
      def export_v3(character)
        data = character.data

        data_hash = {
          "name" => data.name,
          "description" => data.description || "",
          "personality" => data.personality || "",
          "scenario" => data.scenario || "",
          "first_mes" => data.first_mes || "",
          "mes_example" => data.mes_example || "",
          "creator_notes" => data.creator_notes || "",
          "system_prompt" => data.system_prompt || "",
          "post_history_instructions" => data.post_history_instructions || "",
          "alternate_greetings" => data.alternate_greetings || [],
          "tags" => data.tags || [],
          "creator" => data.creator || "",
          "character_version" => data.character_version || "",
          "extensions" => deep_copy(data.extensions || {}),
          # V3 required field
          "group_only_greetings" => data.group_only_greetings || [],
        }

        # Include character_book if present (with V3 lorebook upgrades)
        if data.character_book
          data_hash["character_book"] = upgrade_lorebook_for_v3(deep_copy(data.character_book))
        end

        # Optional V3 fields - only include if present
        data_hash["assets"] = data.assets if data.assets
        data_hash["nickname"] = data.nickname if data.nickname
        data_hash["creator_notes_multilingual"] = data.creator_notes_multilingual if data.creator_notes_multilingual
        data_hash["source"] = data.source if data.source
        data_hash["creation_date"] = data.creation_date if data.creation_date
        data_hash["modification_date"] = data.modification_date if data.modification_date

        {
          "spec" => "chara_card_v3",
          "spec_version" => "3.0",
          "data" => data_hash,
        }
      end

      # Detect the version of a character card hash.
      #
      # @param hash [Hash] raw card hash
      # @return [Symbol] :v1, :v2, :v3, or :unknown
      def detect_version(hash)
        return :unknown unless hash.is_a?(Hash)

        spec = hash["spec"].to_s

        return :v2 if spec == "chara_card_v2"
        return :v3 if spec == "chara_card_v3"
        return :v1 if looks_like_v1?(hash)

        :unknown
      end

      private

      # Extract a hash from various input types.
      #
      # @param input [String, Hash] file path, JSON string, or hash
      # @return [Hash] parsed hash
      def extract_hash(input)
        case input
        when Hash
          input
        when String
          ext = File.extname(input).downcase
          case ext
          when ".json"
            JSON.parse(File.read(input))
          when ".png", ".apng"
            TavernKit::Png::Parser.extract_card_payload(input)
          else
            # Try to parse as JSON string
            begin
              JSON.parse(input)
            rescue JSON::ParserError
              raise ArgumentError, "Unsupported input: expected .json/.png/.apng file path, Hash, or JSON string"
            end
          end
        else
          raise ArgumentError, "Unsupported input type: #{input.class}. Expected String (path) or Hash."
        end
      end

      # Parse a hash into a Character.
      #
      # @param hash [Hash] raw card hash
      # @return [Character]
      def parse_hash(hash)
        unless hash.is_a?(Hash)
          raise InvalidCardError, "Character Card must be a JSON object"
        end

        version = detect_version(hash)

        case version
        when :v2
          parse_v2(hash)
        when :v3
          parse_v3(hash)
        when :v1
          raise UnsupportedVersionError, "Character Card V1 is not supported. Please convert to V2 or V3."
        else
          raise InvalidCardError, "Unknown character card format (spec=#{hash["spec"].inspect})"
        end
      end

      # Parse a V2 card hash into a Character.
      #
      # @param hash [Hash] V2 card hash
      # @return [Character]
      def parse_v2(hash)
        data_hash = hash["data"]
        unless data_hash.is_a?(Hash)
          raise InvalidCardError, "Character Card V2 must contain a 'data' object"
        end

        name = data_hash["name"].to_s
        if name.strip.empty?
          raise InvalidCardError, "Character Card V2 data.name must be a non-empty string"
        end

        tags = data_hash["tags"]
        tags = [] unless tags.is_a?(Array)

        creator = data_hash["creator"].to_s
        character_version = data_hash["character_version"].to_s

        extensions = data_hash["extensions"]
        extensions = {} unless extensions.is_a?(Hash)

        data = Character::Data.new(
          name: name,
          description: data_hash["description"],
          personality: data_hash["personality"],
          scenario: data_hash["scenario"],
          first_mes: data_hash["first_mes"],
          mes_example: data_hash["mes_example"],
          creator_notes: data_hash["creator_notes"],
          system_prompt: data_hash["system_prompt"],
          post_history_instructions: data_hash["post_history_instructions"],
          alternate_greetings: data_hash["alternate_greetings"] || [],
          character_book: data_hash["character_book"],
          tags: tags,
          creator: creator,
          character_version: character_version,
          extensions: extensions,
          # V3 fields - not present in V2, default to nil/empty
          group_only_greetings: [],
          assets: nil,
          nickname: nil,
          creator_notes_multilingual: nil,
          source: nil,
          creation_date: nil,
          modification_date: nil,
        )

        Character.new(data: data, source_version: :v2, raw: hash)
      end

      # Parse a V3 card hash into a Character.
      #
      # @param hash [Hash] V3 card hash
      # @return [Character]
      def parse_v3(hash)
        data_hash = hash["data"]
        unless data_hash.is_a?(Hash)
          raise InvalidCardError, "Character Card V3 must contain a 'data' object"
        end

        name = data_hash["name"].to_s
        if name.strip.empty?
          raise InvalidCardError, "Character Card V3 data.name must be a non-empty string"
        end

        tags = data_hash["tags"]
        tags = [] unless tags.is_a?(Array)

        creator = data_hash["creator"].to_s
        character_version = data_hash["character_version"].to_s

        extensions = data_hash["extensions"]
        extensions = {} unless extensions.is_a?(Hash)

        data = Character::Data.new(
          name: name,
          description: data_hash["description"],
          personality: data_hash["personality"],
          scenario: data_hash["scenario"],
          first_mes: data_hash["first_mes"],
          mes_example: data_hash["mes_example"],
          creator_notes: data_hash["creator_notes"],
          system_prompt: data_hash["system_prompt"],
          post_history_instructions: data_hash["post_history_instructions"],
          alternate_greetings: data_hash["alternate_greetings"] || [],
          character_book: data_hash["character_book"],
          tags: tags,
          creator: creator,
          character_version: character_version,
          extensions: extensions,
          # V3 fields
          group_only_greetings: data_hash["group_only_greetings"] || [],
          assets: data_hash["assets"],
          nickname: data_hash["nickname"],
          creator_notes_multilingual: data_hash["creator_notes_multilingual"],
          source: data_hash["source"],
          creation_date: data_hash["creation_date"],
          modification_date: data_hash["modification_date"],
        )

        Character.new(data: data, source_version: :v3, raw: hash)
      end

      # Check if a hash looks like a V1 character card.
      #
      # @param hash [Hash] raw card hash
      # @return [Boolean]
      def looks_like_v1?(hash)
        return false if hash.key?("spec") || hash.key?("data")

        V1_REQUIRED_FIELDS.all? { |field| hash.key?(field) }
      end

      # Extract V3-only fields from character data.
      #
      # @param data [Character::Data]
      # @return [Hash]
      def extract_v3_extras(data)
        extras = {}
        extras["group_only_greetings"] = data.group_only_greetings if data.group_only_greetings&.any?
        extras["assets"] = data.assets if data.assets
        extras["nickname"] = data.nickname if data.nickname
        extras["creator_notes_multilingual"] = data.creator_notes_multilingual if data.creator_notes_multilingual
        extras["source"] = data.source if data.source
        extras["creation_date"] = data.creation_date if data.creation_date
        extras["modification_date"] = data.modification_date if data.modification_date
        extras
      end

      # Upgrade a lorebook to V3 format (add use_regex to entries).
      #
      # @param lorebook [Hash]
      # @return [Hash]
      def upgrade_lorebook_for_v3(lorebook)
        return lorebook unless lorebook.is_a?(Hash)

        lorebook["extensions"] ||= {}
        entries = lorebook["entries"]
        return lorebook unless entries.is_a?(Array)

        entries.each do |entry|
          next unless entry.is_a?(Hash)

          entry["extensions"] ||= {}
          # V3 requires use_regex boolean
          entry["use_regex"] = Coerce.bool(entry["use_regex"], default: false)
          # Normalize keys to arrays
          entry["keys"] = Array(entry["keys"]) if entry.key?("keys")
          entry["secondary_keys"] = Array(entry["secondary_keys"]) if entry.key?("secondary_keys")
        end

        lorebook
      end

      # Deep copy an object via JSON round-trip.
      #
      # @param obj [Object]
      # @return [Object]
      def deep_copy(obj)
        JSON.parse(JSON.generate(obj))
      end
    end
  end
end
