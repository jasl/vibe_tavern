# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module TavernKit
  module Ingest
    module Byaf
      module_function

      def call(path, **zip_limits)
        # Pass the path directly to avoid loading the whole archive into memory.
        parsed = TavernKit::Archive::ByafParser.new(path, **zip_limits).parse

        warnings = []

        character_paths = Array(parsed.manifest["characters"]).map(&:to_s)
        warnings << "BYAF manifest contains more than one character; only the first one will be imported" if character_paths.length > 1

        tmpdir = nil
        files = []

        image_defs = character_image_defs(parsed)
        background_defs = scenario_background_defs(parsed)
        asset_defs = image_defs + background_defs

        assets = asset_defs.map do |defn|
          Bundle::Asset.new(
            container_path: path,
            source_path: defn[:source_path],
            kind: defn[:kind],
            metadata: defn[:metadata],
            zip_limits: zip_limits,
          )
        end

        main_image_path = nil

        if asset_defs.any?
          TavernKit::Archive::ZipReader.open(path, **zip_limits) do |zip|
            # Check referenced assets exist (cheap) and pick a main image.
            main_def = image_defs.find { |d| zip.entry?(d[:source_path]) }

            missing_assets = asset_defs.reject { |d| zip.entry?(d[:source_path]) }
            missing_assets.each { |d| warnings << "Missing BYAF asset #{d[:source_path].inspect}" }

            if main_def
              begin
                bytes = zip.read(main_def[:source_path])
                tmpdir = Dir.mktmpdir("tavern_kit-byaf-")
                extracted_path = write_tmp_file!(tmpdir, main_def[:source_path], bytes)
                files << Bundle::Resource.new(
                  path: extracted_path,
                  source_path: main_def[:source_path],
                  kind: :main_image,
                  metadata: main_def[:metadata],
                )
                main_image_path = extracted_path
              rescue TavernKit::Archive::ZipError => e
                warnings << "Failed to extract BYAF main image #{main_def[:source_path].inspect}: #{e.message}"
                if tmpdir && Dir.exist?(tmpdir)
                  FileUtils.remove_entry_secure(tmpdir)
                  tmpdir = nil
                end
              end
            end
          end
        end

        scenarios = parsed.scenarios.map { |s| deep_underscore_keys(s) }

        Bundle.new(
          character: TavernKit::CharacterCard.load_hash(parsed.card_hash),
          main_image_path: main_image_path,
          files: files,
          assets: assets,
          scenarios: scenarios,
          warnings: warnings,
          tmpdir: tmpdir,
        )
      rescue StandardError
        # Best-effort cleanup if we created temp files but failed before
        # returning a bundle (Bundle#close won't run).
        FileUtils.remove_entry_secure(tmpdir) if defined?(tmpdir) && tmpdir && Dir.exist?(tmpdir)
        raise
      end

      def character_image_defs(parsed)
        character_path = Array(parsed.manifest["characters"]).first.to_s
        base_dir = ::File.dirname(character_path)

        Array(parsed.character["images"]).filter_map.with_index do |img, idx|
          next nil unless img.is_a?(Hash)

          rel = img["path"].to_s.strip
          next nil if rel.empty?

          source_path = ::File.join(base_dir, rel)
          {
            source_path: source_path,
            kind: :character_image,
            metadata: {
              label: img["label"].to_s,
              index: idx,
            },
          }
        end
      end

      def scenario_background_defs(parsed)
        by_path = Hash.new { |h, k| h[k] = [] }

        parsed.scenarios.each_with_index do |scenario, idx|
          next unless scenario.is_a?(Hash)

          path = scenario["backgroundImage"].to_s.strip
          next if path.empty?

          by_path[path] << idx
        end

        by_path.map do |source_path, indices|
          {
            source_path: source_path,
            kind: :background_image,
            metadata: { scenario_indices: indices },
          }
        end
      end

      def deep_underscore_keys(value)
        case value
        when Array then value.map { |v| deep_underscore_keys(v) }
        when Hash
          value.each_with_object({}) do |(k, v), out|
            out[TavernKit::Utils.underscore(k.to_s)] = deep_underscore_keys(v)
          end
        else value
        end
      end

      def write_tmp_file!(tmpdir, source_path, bytes)
        raise ArgumentError, "tmpdir is required" if tmpdir.to_s.strip.empty?

        out = ::File.join(tmpdir, source_path)
        ::FileUtils.mkdir_p(::File.dirname(out))
        ::File.binwrite(out, bytes)
        out
      end
    end
  end
end
