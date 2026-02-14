# frozen_string_literal: true

require "yaml"

module AgentCore
  module Resources
    module Skills
      # Parses YAML frontmatter from SKILL.md files.
      #
      # Frontmatter is delimited by `---` lines at the top of the file.
      # Supports strict mode (raises on errors) and lenient mode (returns nil).
      module Frontmatter
        # Allowed top-level frontmatter fields per Agent Skills spec.
        ALLOWED_FIELDS = %i[name description license allowed_tools metadata compatibility].freeze
        MAX_DESCRIPTION_CHARS = 1024
        MAX_COMPATIBILITY_CHARS = 500

        module_function

        # Parse frontmatter from a SKILL.md content string.
        #
        # @param content_string [String] The full SKILL.md content
        # @param expected_name [String, nil] Expected skill name (for validation)
        # @param path [String, nil] File path (used to infer expected name from directory)
        # @param strict [Boolean] Whether to raise on errors
        # @return [Array(Hash, String), Array(nil, String)] [frontmatter, body] or [nil, body] on error
        def parse(content_string, expected_name: nil, path: nil, strict: true)
          raw = content_string.to_s
          lines = raw.lines
          body_fallback = raw

          unless lines.first&.strip == "---"
            return invalid(strict, "frontmatter must start with ---", body_fallback)
          end

          closing_index = nil
          lines.each_with_index do |line, idx|
            next if idx == 0

            if line.strip == "---"
              closing_index = idx
              break
            end
          end

          unless closing_index
            return invalid(strict, "frontmatter is missing closing --- delimiter", body_fallback)
          end

          frontmatter_yaml = lines[1...closing_index].join
          body_string = lines[(closing_index + 1)..].to_a.join

          begin
            parsed = YAML.safe_load(frontmatter_yaml, permitted_classes: [], permitted_symbols: [], aliases: false)
          rescue Psych::Exception => e
            return invalid(strict, "invalid YAML frontmatter: #{e.message}", body_string)
          end

          parsed = {} if parsed.nil?
          unless parsed.is_a?(Hash)
            return invalid(strict, "frontmatter must be a YAML mapping (Hash)", body_string)
          end

          frontmatter = symbolize_top_level(parsed)
          extra_fields = frontmatter.keys - ALLOWED_FIELDS
          if extra_fields.any?
            return invalid(
              strict,
              "Unexpected fields in frontmatter: #{extra_fields.map(&:to_s).sort.join(", ")}. " \
              "Only #{ALLOWED_FIELDS.map(&:to_s).sort} are allowed.",
              body_string
            )
          end

          metadata, metadata_error = normalize_metadata(frontmatter.fetch(:metadata, nil))
          return invalid(strict, metadata_error, body_string) if metadata.nil?

          frontmatter[:metadata] = metadata

          name_value = frontmatter.fetch(:name, nil)
          description_value = frontmatter.fetch(:description, nil)

          if strict
            return invalid(strict, "frontmatter.name must be a non-empty string", body_string) unless name_value.is_a?(String)
            return invalid(strict, "frontmatter.description must be a non-empty string", body_string) unless description_value.is_a?(String)
          end

          name = normalize_name(name_value)
          description = description_value.to_s.strip

          return invalid(strict, "frontmatter.name is required", body_string) if name.empty?
          return invalid(strict, "frontmatter.description is required", body_string) if description.empty?

          if strict && description.length > MAX_DESCRIPTION_CHARS
            return invalid(strict, "frontmatter.description must be <= #{MAX_DESCRIPTION_CHARS} chars", body_string)
          end

          if frontmatter.key?(:compatibility)
            compatibility_raw = frontmatter.fetch(:compatibility, nil)

            if strict && !compatibility_raw.is_a?(String)
              return invalid(strict, "frontmatter.compatibility must be a string", body_string)
            end

            compatibility = compatibility_raw.to_s.strip
            if strict && compatibility.empty?
              return invalid(strict, "frontmatter.compatibility must be 1-#{MAX_COMPATIBILITY_CHARS} chars", body_string)
            end

            compatibility = nil if compatibility.empty?

            if strict && compatibility && compatibility.length > MAX_COMPATIBILITY_CHARS
              return invalid(strict, "frontmatter.compatibility must be <= #{MAX_COMPATIBILITY_CHARS} chars", body_string)
            end

            frontmatter[:compatibility] = compatibility
          end

          unless valid_name?(name)
            return invalid(strict, "invalid skill name: #{name.inspect}", body_string)
          end

          expected = expected_skill_name(expected_name: expected_name, path: path)
          if expected && expected != name
            return invalid(strict, "skill name must match directory name: expected #{expected.inspect}, got #{name.inspect}", body_string)
          end

          frontmatter[:name] = name
          frontmatter[:description] = description

          [frontmatter, body_string]
        end

        # Check if a skill name is valid.
        #
        # @param name [String]
        # @return [Boolean]
        def valid_name?(name)
          normalized = normalize_name(name)
          return false if normalized.empty?
          return false if normalized.length > 64

          return false if normalized != normalized.downcase
          return false if normalized.start_with?("-") || normalized.end_with?("-")
          return false if normalized.include?("--")

          normalized.each_char do |ch|
            next if ch == "-"
            return false unless alnum_char?(ch)
          end

          true
        end

        def expected_skill_name(expected_name:, path:)
          expected = expected_name.to_s.strip
          expected = nil if expected.empty?

          if expected.nil? && path
            dir = File.dirname(path.to_s)
            base = File.basename(dir)
            expected = base.to_s.strip
            expected = nil if expected.empty?
          end

          expected ? normalize_name(expected) : nil
        end
        private_class_method :expected_skill_name

        def symbolize_top_level(hash)
          hash.each_with_object({}) do |(k, v), out|
            key = k.to_s.strip
            next if key.empty?

            key = key.tr("-", "_")
            out[key.to_sym] = v
          end
        end
        private_class_method :symbolize_top_level

        def normalize_metadata(value)
          return [{}, nil] if value.nil?

          unless value.is_a?(Hash)
            return [nil, "frontmatter.metadata must be a Hash"]
          end

          out = {}

          value.each do |k, v|
            key = k.to_s
            next if key.strip.empty?

            out[key] = v.to_s
          end

          [out, nil]
        end
        private_class_method :normalize_metadata

        def normalize_name(value)
          s = value.to_s.strip
          return "" if s.empty?

          s.unicode_normalize(:nfkc)
        end
        private_class_method :normalize_name

        def alnum_char?(ch)
          ch.match?(/\A[\p{L}\p{N}]\z/)
        end
        private_class_method :alnum_char?

        def invalid(strict, message, body_string)
          raise ArgumentError, message if strict

          [nil, body_string.to_s]
        end
        private_class_method :invalid
      end
    end
  end
end
