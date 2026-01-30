# frozen_string_literal: true

require "json"
require "set"
require "time"

require_relative "zip_reader"

module TavernKit
  module Archive
    # BYAF (Backyard Archive Format) importer.
    #
    # Reference (JS): resources/byaf
    #
    # This importer is intentionally focused on:
    # - producing a CCv2-compatible hash (a common import target)
    # - placeholder normalization ({user}/{character} -> {{user}}/{{char}})
    #
    # It does NOT attempt to extract assets or replicate app-specific behaviors
    # (background extraction, chat file generation, etc). Downstream apps can
    # consume assets via ZipReader directly.
    class ByafParser
      def initialize(data, **zip_limits)
        @data = data
        @zip_limits = zip_limits
      end

      # Parse BYAF ZIP bytes into a Character Card v2 hash.
      #
      # @return [Hash] card hash in CCv2 format
      def parse_character
        ZipReader.open(@data, **@zip_limits) do |zip|
          manifest = zip.read_json("manifest.json")
          character = read_character(zip, manifest)
          scenarios = read_scenarios(zip, manifest)
          build_card(manifest, character, scenarios)
        end
      rescue TavernKit::Archive::ZipError => e
        raise TavernKit::Archive::ByafParseError, "Invalid BYAF file: #{e.message}"
      end

      # Replace known BYAF placeholders with ST-style placeholder syntax.
      #
      # - `#{user}:` -> `{{user}}:`
      # - `#{character}:` -> `{{char}}:`
      # - `{user}` -> `{{user}}` (but do not touch `{{user}}`)
      # - `{character}` -> `{{char}}` (but do not touch `{{character}}`)
      def self.replace_macros(str)
        String(str || "")
          .gsub(/#\{user\}:/i, "{{user}}:")
          .gsub(/#\{character\}:/i, "{{char}}:")
          .gsub(/\{character\}(?!\})/i, "{{char}}")
          .gsub(/\{user\}(?!\})/i, "{{user}}")
      end

      private

      def read_optional_json(zip, path)
        return nil unless zip.entry?(path)

        zip.read_json(path)
      rescue TavernKit::Archive::ZipError
        nil
      end

      def read_character(zip, manifest)
        characters = Array(manifest["characters"])
        raise TavernKit::Archive::ZipError, "Invalid BYAF file: missing characters array" if characters.empty?

        path = characters.first.to_s
        raise TavernKit::Archive::ZipError, "Invalid BYAF file: missing character path" if path.strip.empty?

        zip.read_json(path)
      end

      def read_scenarios(zip, manifest)
        paths = Array(manifest["scenarios"]).map(&:to_s).map(&:strip).reject(&:empty?)
        return [{}] if paths.empty?

        scenarios = paths.filter_map { |p| read_optional_json(zip, p) }
        scenarios.empty? ? [{}] : scenarios
      end

      def build_card(manifest, character, scenarios)
        author = manifest.is_a?(Hash) ? (manifest["author"] || {}) : {}
        scenario = scenarios.first || {}

        name = character["name"] || character["displayName"] || ""
        display_name = character["displayName"]

        first_message_text = scenario.dig("firstMessages", 0, "text")

        data = {
          "name" => name.to_s,
          "description" => self.class.replace_macros(character["persona"]),
          "personality" => "",
          "scenario" => self.class.replace_macros(scenario["narrative"]),
          "first_mes" => self.class.replace_macros(first_message_text),
          "mes_example" => format_example_messages(scenario["exampleMessages"]),
          "creator_notes" => author.is_a?(Hash) ? author["backyardURL"].to_s : "",
          "system_prompt" => self.class.replace_macros(scenario["formattingInstructions"]),
          "post_history_instructions" => "",
          "alternate_greetings" => format_alternate_greetings(scenarios),
          "character_book" => convert_character_book(character["loreItems"]),
          "tags" => (character["isNSFW"] == true ? ["nsfw"] : []),
          "creator" => author.is_a?(Hash) ? author["name"].to_s : "",
          "character_version" => "",
          "extensions" => build_extensions(display_name),
        }

        data.delete("character_book") if data["character_book"].nil?

        {
          "spec" => "chara_card_v2",
          "spec_version" => "2.0",
          "data" => data,
          # Non-standard spec extension used by some apps.
          "create_date" => Time.now.iso8601,
        }
      end

      def format_example_messages(examples)
        return "" unless examples.is_a?(Array)

        out = +""
        examples.each do |example|
          next unless example.is_a?(Hash)

          text = example["text"]
          next if text.to_s.strip.empty?

          out << "<START>\n"
          out << self.class.replace_macros(text)
          out << "\n"
        end

        out.rstrip
      end

      def format_alternate_greetings(scenarios)
        list = Array(scenarios)
        return [] if list.length <= 1

        first = list.dig(0, "firstMessages", 0, "text")

        greetings = Set.new
        list.drop(1).each do |scenario|
          next unless scenario.is_a?(Hash)

          msg = scenario.dig("firstMessages", 0, "text")
          next if msg.to_s.strip.empty?
          next if msg == first

          greetings << self.class.replace_macros(msg)
        end

        greetings.to_a
      end

      def convert_character_book(items)
        return nil unless items.is_a?(Array) && items.any?

        {
          "entries" => items.each_with_index.filter_map do |item, idx|
            next nil unless item.is_a?(Hash)

            keys = self.class.replace_macros(item["key"])
              .to_s
              .split(",")
              .map(&:strip)
              .reject(&:empty?)

            {
              "keys" => keys,
              "content" => self.class.replace_macros(item["value"]),
              "extensions" => {},
              "enabled" => true,
              "insertion_order" => idx,
            }
          end,
          "extensions" => {},
        }
      end

      def build_extensions(display_name)
        s = display_name.to_s
        return {} if s.strip.empty?

        { "display_name" => s }
      end
    end
  end
end
