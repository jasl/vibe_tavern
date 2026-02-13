# frozen_string_literal: true

require "yaml"

module TavernKit
  module VibeTavern
    module Tools
      module Skills
        module Frontmatter
          NAME_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/.freeze
          MAX_DESCRIPTION_CHARS = 1024
          MAX_COMPATIBILITY_CHARS = 500

          module_function

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
            metadata, metadata_error = normalize_metadata(frontmatter.fetch(:metadata, nil), strict: strict)
            return invalid(strict, metadata_error, body_string) if metadata.nil?

            frontmatter[:metadata] = metadata

            name = frontmatter.fetch(:name, nil).to_s.strip
            description = frontmatter.fetch(:description, nil).to_s.strip

            return invalid(strict, "frontmatter.name is required", body_string) if name.empty?
            return invalid(strict, "frontmatter.description is required", body_string) if description.empty?

            if strict && description.length > MAX_DESCRIPTION_CHARS
              return invalid(strict, "frontmatter.description must be <= #{MAX_DESCRIPTION_CHARS} chars", body_string)
            end

            compatibility = frontmatter.fetch(:compatibility, nil)
            compatibility = compatibility.to_s.strip unless compatibility.nil?
            compatibility = nil if compatibility&.empty?
            if strict && compatibility && compatibility.length > MAX_COMPATIBILITY_CHARS
              return invalid(strict, "frontmatter.compatibility must be <= #{MAX_COMPATIBILITY_CHARS} chars", body_string)
            end
            frontmatter[:compatibility] = compatibility if frontmatter.key?(:compatibility)

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

          def valid_name?(name)
            name = name.to_s
            return false if name.empty?
            return false if name.bytesize > 64

            NAME_PATTERN.match?(name)
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

            expected
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

          def normalize_metadata(value, strict:)
            return [{}, nil] if value.nil?

            unless value.is_a?(Hash)
              return [nil, "frontmatter.metadata must be a Hash"]
            end

            out = {}

            value.each do |k, v|
              key = k.to_s
              next if key.strip.empty?

              if strict
                unless v.is_a?(String)
                  return [nil, "frontmatter.metadata must be a string-to-string map"]
                end

                out[key] = v
              else
                out[key] = v.to_s
              end
            end

            [out, nil]
          end
          private_class_method :normalize_metadata

          def invalid(strict, message, body_string)
            raise ArgumentError, message if strict

            [nil, body_string.to_s]
          end
          private_class_method :invalid
        end
      end
    end
  end
end
