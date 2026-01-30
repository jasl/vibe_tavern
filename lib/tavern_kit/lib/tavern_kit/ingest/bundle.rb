# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module TavernKit
  module Ingest
    # A normalized import result returned by TavernKit::Ingest.
    #
    # - `character` is always present.
    # - `main_image_path` is optional (e.g., JSON-only cards).
    # - `files` contains extracted assets (when applicable).
    # - `scenarios` is optional, used by BYAF.
    #
    # Bundles may own a temp directory for extracted files. If so, call #close
    # (or use TavernKit::Ingest.open with a block) to ensure cleanup.
    class Bundle
      Resource = Data.define(:path, :source_path, :kind, :metadata) do
        def filename = File.basename(path.to_s)
      end

      def initialize(character:, main_image_path: nil, files: [], scenarios: nil, warnings: [], tmpdir: nil)
        @character = character
        @main_image_path = main_image_path
        @files = files
        @scenarios = scenarios
        @warnings = warnings
        @tmpdir = tmpdir

        @closed = false
      end

      attr_reader :character, :main_image_path, :files, :scenarios, :warnings, :tmpdir

      def closed? = @closed

      def close
        return if @closed

        @closed = true

        return unless @tmpdir
        return unless Dir.exist?(@tmpdir)

        FileUtils.remove_entry_secure(@tmpdir)
      end
    end
  end
end
