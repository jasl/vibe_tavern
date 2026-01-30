# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module TavernKit
  module Ingest
    module CharX
      module_function

      def call(path, **zip_limits)
        tmpdir = nil

        TavernKit::Archive::CharX.open(path, **zip_limits) do |pkg|
          asset_defs = embedded_asset_defs(pkg.card_hash)
          embedded_paths = pkg.embedded_asset_paths

          if embedded_paths.any?
            tmpdir = Dir.mktmpdir("tavern_kit-charx-")
          end

          files = embedded_paths.map do |source_path|
            bytes = pkg.read_asset(source_path)
            extracted_path = write_tmp_file!(tmpdir, source_path, bytes)

            Bundle::Resource.new(
              path: extracted_path,
              source_path: source_path,
              kind: :asset,
              metadata: asset_defs.find { |a| a[:source_path] == source_path }&.fetch(:metadata),
            )
          end

          main_image_path = resolve_main_image_path(asset_defs, files)

          Bundle.new(
            character: pkg.character,
            main_image_path: main_image_path,
            files: files,
            warnings: [],
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

      def resolve_main_image_path(asset_defs, files)
        selected_source_path =
          asset_defs.find { |a| a[:type].downcase == "icon" && a[:name].downcase == "main" }&.dig(:source_path) ||
          asset_defs.find { |a| a[:type].downcase == "icon" }&.dig(:source_path)

        files.find { |f| f.source_path == selected_source_path }&.path
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
