# frozen_string_literal: true

require "fileutils"
require "set"
require "tmpdir"

module TavernKit
  module Ingest
    module CharX
      module_function

      def call(path, **zip_limits)
        tmpdir = nil

        TavernKit::Archive::CharX.open(path, **zip_limits) do |pkg|
          asset_defs = embedded_asset_defs(pkg.card_hash)
          main_source_path = resolve_main_source_path(asset_defs)

          warnings = []

          existing = pkg.entry_paths.to_set
          missing_assets = asset_defs.reject { |d| existing.include?(d[:source_path]) }
          missing_assets.each { |d| warnings << "Missing CHARX asset #{d[:source_path].inspect}" }

          files = []
          if main_source_path
            begin
              bytes = pkg.read_asset(main_source_path)
              tmpdir = Dir.mktmpdir("tavern_kit-charx-")
              extracted_path = write_tmp_file!(tmpdir, main_source_path, bytes)
              files << Bundle::Resource.new(
                path: extracted_path,
                source_path: main_source_path,
                kind: :main_image,
                metadata: asset_defs.find { |a| a[:source_path] == main_source_path }&.fetch(:metadata),
              )
            rescue TavernKit::Archive::ZipError => e
              warnings << "Failed to extract CHARX main image #{main_source_path.inspect}: #{e.message}"
              if tmpdir && Dir.exist?(tmpdir)
                FileUtils.remove_entry_secure(tmpdir)
                tmpdir = nil
              end
            end
          end

          assets = asset_defs.map do |defn|
            Bundle::Asset.new(
              container_path: path,
              source_path: defn[:source_path],
              kind: :asset,
              metadata: defn[:metadata],
              zip_limits: zip_limits,
            )
          end

          main_image_path = files.first&.path

          Bundle.new(
            character: pkg.character,
            main_image_path: main_image_path,
            files: files,
            assets: assets,
            warnings: warnings,
            tmpdir: tmpdir,
          )
        end
      rescue StandardError
        FileUtils.remove_entry_secure(tmpdir) if tmpdir && Dir.exist?(tmpdir)
        raise
      end

      def embedded_asset_defs(card_hash)
        Array(card_hash.dig("data", "assets")).filter_map do |asset|
          next nil unless asset.is_a?(Hash)

          uri = asset["uri"].to_s
          next nil unless uri.start_with?("embeded://")

          {
            source_path: uri.delete_prefix("embeded://"),
            type: asset["type"].to_s,
            name: asset["name"].to_s,
            metadata: asset,
          }
        end
      end

      def resolve_main_source_path(asset_defs)
        asset_defs.find { |a| a[:type].downcase == "icon" && a[:name].downcase == "main" }&.dig(:source_path) ||
          asset_defs.find { |a| a[:type].downcase == "icon" }&.dig(:source_path)
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
