# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Lore
      # Import SillyTavern native World Info JSON into core Lore::Book/Entry.
      #
      # This importer is hash-only. The caller is responsible for file I/O and
      # `JSON.parse` (if the source is a JSON string/file).
      #
      # The ST format differs from CCv2/CCv3 Character Book:
      # - entry keys use `key` / `keysecondary` instead of `keys` / `secondary_keys`
      # - disabled entries use `disable` (inverted enabled)
      # - order uses `order` (mapped to insertion_order)
      # - position is often numeric (mapped to canonical string positions)
      #
      # All ST-only fields are placed under `extensions` in snake_case form.
      class WorldInfoImporter
        def self.load_hash(hash, strict: false)
          raise ArgumentError, "World Info must be a Hash" unless hash.is_a?(Hash)

          new(hash, strict: strict).to_book
        end

        def initialize(hash, strict:)
          @hash = TavernKit::Utils.deep_stringify_keys(hash)
          @strict = strict == true
        end

        def to_book
          h = @hash
          acc = TavernKit::Utils::HashAccessor.wrap(h)

          recursive_scanning_raw = acc["recursive_scanning", "recursiveScanning"]
          recursive_scanning = recursive_scanning_raw.nil? ? nil : TavernKit::Coerce.bool(recursive_scanning_raw, default: false)

          TavernKit::Lore::Book.new(
            name: presence_str(acc["name"]),
            description: presence_str(acc["description"]),
            scan_depth: int_or_nil(acc["scan_depth", "scanDepth"]),
            token_budget: int_or_nil(acc["token_budget", "tokenBudget"]),
            recursive_scanning: recursive_scanning,
            extensions: extract_book_extensions(h),
            entries: extract_entries(acc["entries"]),
          )
        end

        private

        BOOK_RESERVED_KEYS = %w[
          _comment
          name
          description
          scan_depth
          scanDepth
          token_budget
          tokenBudget
          recursive_scanning
          recursiveScanning
          entries
          extensions
        ].freeze

        ENTRY_RESERVED_KEYS = %w[
          _comment
          uid
          id
          key
          keys
          keysecondary
          keySecondary
          secondary_keys
          secondaryKeys
          content
          disable
          enabled
          order
          insertion_order
          insertionOrder
          priority
          use_regex
          useRegex
          case_sensitive
          caseSensitive
          constant
          name
          comment
          memo
          selective
          position
          pos
          extensions
        ].freeze

        POSITION_MAP = {
          0 => "before_char_defs",
          1 => "after_char_defs",
          2 => "top_of_an",
          3 => "bottom_of_an",
          4 => "at_depth",
          5 => "before_example_messages",
          6 => "after_example_messages",
          7 => "outlet",
          "before_char" => "before_char_defs",
          "before_char_defs" => "before_char_defs",
          "after_char" => "after_char_defs",
          "after_char_defs" => "after_char_defs",
          "before_main" => "before_char_defs",
          "after_main" => "after_char_defs",
          "before_example_messages" => "before_example_messages",
          "after_example_messages" => "after_example_messages",
          "top_an" => "top_of_an",
          "top_of_an" => "top_of_an",
          "bottom_an" => "bottom_of_an",
          "bottom_of_an" => "bottom_of_an",
          "@d" => "at_depth",
          "at_depth" => "at_depth",
          "depth" => "at_depth",
          "in_chat" => "at_depth",
          "outlet" => "outlet",
          "personality" => "personality",
          "scenario" => "scenario",
        }.freeze

        def extract_book_extensions(hash)
          ext = {}

          if hash["extensions"].is_a?(Hash)
            ext.merge!(deep_snake_case_keys(hash["extensions"]))
          end

          hash.each do |key, value|
            next if BOOK_RESERVED_KEYS.include?(key)
            next if key.start_with?("_")

            canonical = TavernKit::Utils.underscore(key)
            v2 = deep_snake_case_keys(value)

            if canonical == key
              ext[canonical] = v2
            else
              ext[canonical] = v2 unless ext.key?(canonical)
            end
          end

          ext
        end

        def extract_entries(raw_entries)
          items =
            case raw_entries
            when Array
              raw_entries
            when Hash
              raw_entries.sort_by do |key, _|
                k = key.to_s
                k.match?(/\A\d+\z/) ? k.to_i : k
              end.map { |_, value| value }
            else
              []
            end

          items.filter_map { |entry| build_entry(entry) }
        end

        def build_entry(value)
          unless value.is_a?(Hash)
            return nil unless @strict

            raise TavernKit::SillyTavern::LoreParseError, "World Info entry must be a Hash, got: #{value.class}"
          end

          h = TavernKit::Utils.deep_stringify_keys(value)
          acc = TavernKit::Utils::HashAccessor.wrap(h)

          keys = normalize_string_array(acc["keys", "key"])
          if keys.empty?
            return nil unless @strict

            raise TavernKit::SillyTavern::LoreParseError, "World Info entry has no keys"
          end

          secondary_keys = normalize_string_array(acc["secondary_keys", "keysecondary"])

          selective =
            if acc["selective"].nil?
              secondary_keys.any? ? true : nil
            else
              TavernKit::Coerce.bool(acc["selective"], default: false)
            end

          disable = acc["disable"]
          enabled =
            if disable.nil?
              TavernKit::Coerce.bool(acc.fetch("enabled", default: true), default: true)
            else
              !TavernKit::Coerce.bool(disable, default: false)
            end

          TavernKit::Lore::Entry.new(
            keys: keys,
            content: acc.fetch("content", default: "").to_s,
            enabled: enabled,
            insertion_order: acc.fetch("insertion_order", "order", "insertionOrder", "priority", default: 100).to_i,
            use_regex: TavernKit::Coerce.bool(acc["use_regex", "useRegex"], default: false),
            case_sensitive: coerce_optional_bool(acc["case_sensitive", "caseSensitive"]),
            constant: coerce_optional_bool(acc["constant"], default: false),
            name: presence_str(acc["name"]),
            priority: coerce_optional_int(acc["priority"]),
            id: acc["uid", "id"]&.to_s,
            comment: presence_str(acc["comment", "memo"]),
            selective: selective,
            secondary_keys: secondary_keys,
            position: coerce_position(acc["position", "pos"]),
            extensions: extract_entry_extensions(h),
          )
        rescue ArgumentError
          raise if @strict

          nil
        end

        def extract_entry_extensions(entry_hash)
          ext = {}

          if entry_hash["extensions"].is_a?(Hash)
            ext.merge!(deep_snake_case_keys(entry_hash["extensions"]))
          end

          entry_hash.each do |key, value|
            next if ENTRY_RESERVED_KEYS.include?(key)
            next if key.start_with?("_")

            canonical = TavernKit::Utils.underscore(key)
            v2 = deep_snake_case_keys(value)

            if canonical == key
              ext[canonical] = v2
            else
              ext[canonical] = v2 unless ext.key?(canonical)
            end
          end

          char_filter = ext["character_filter"]
          if char_filter.is_a?(Hash)
            ext["character_filter_names"] ||= normalize_string_array(char_filter["names"])
            ext["character_filter_tags"] ||= normalize_string_array(char_filter["tags"])

            exclude = char_filter["is_exclude"]
            exclude = char_filter["exclude"] if exclude.nil?
            ext["character_filter_exclude"] ||= exclude unless exclude.nil?
          end

          ext
        end

        def deep_snake_case_keys(value)
          case value
          when Array
            value.map { |v| deep_snake_case_keys(v) }
          when Hash
            value.each_with_object({}) do |(k, v), out|
              raw = k.to_s
              canonical = TavernKit::Utils.underscore(raw)
              v2 = deep_snake_case_keys(v)

              if canonical == raw
                out[canonical] = v2
              else
                out[canonical] = v2 unless out.key?(canonical)
              end
            end
          else
            value
          end
        end

        def normalize_string_array(value)
          Array(value).map(&:to_s).map(&:strip).reject(&:empty?)
        end

        def int_or_nil(value)
          return nil if value.nil?

          s = value.to_s.strip
          return nil if s.empty?

          s.to_i
        end

        def coerce_optional_bool(value, default: nil)
          return default if value.nil?

          TavernKit::Coerce.bool(value, default: default.nil? ? false : default)
        end

        def coerce_optional_int(value)
          return nil if value.nil?

          s = value.to_s.strip
          return nil if s.empty?

          s.to_i
        end

        def coerce_position(value)
          return nil if value.nil?

          if value.is_a?(Integer)
            POSITION_MAP[value]
          else
            s = value.to_s.strip
            return nil if s.empty?

            POSITION_MAP[s] || POSITION_MAP[s.downcase] || TavernKit::Utils.underscore(s)
          end
        end

        def presence_str(value)
          v = TavernKit::Utils.presence(value)
          v.nil? ? nil : v.to_s
        end
      end
    end
  end
end
