# frozen_string_literal: true

require_relative "ingest/bundle"
require_relative "ingest/byaf"
require_relative "ingest/charx"
require_relative "ingest/png"

module TavernKit
  # File-based ingestion helpers for untrusted external formats.
  #
  # Core objects (Character, Lore, Prompt) operate on Ruby hashes/objects.
  # This namespace provides safe-ish adapters to load common on-disk formats
  # (PNG/APNG wrappers, ZIP-based containers like BYAF/CHARX).
  module Ingest
    @handlers_by_ext = {}

    class << self
      def register(ext, handler = nil, &block)
        handler ||= block
        raise ArgumentError, "handler is required" unless handler

        @handlers_by_ext[normalize_ext(ext)] = handler
      end

      # Open an ingested bundle from a file path.
      #
      # If a block is given, the bundle is automatically closed (tmp cleanup).
      def open(path, **kwargs)
        bundle = open_bundle(path, **kwargs)
        return bundle unless block_given?

        begin
          yield bundle
        ensure
          bundle.close
        end
      end

      def open_bundle(path, **kwargs)
        raise ArgumentError, "path is required" if path.to_s.strip.empty?
        raise ArgumentError, "file not found: #{path.inspect}" unless File.file?(path)

        ext = File.extname(path.to_s).downcase
        handler = @handlers_by_ext[ext]
        raise ArgumentError, "Unsupported file type: #{ext.inspect}" unless handler

        handler.call(path, **kwargs)
      end

      def handlers
        @handlers_by_ext.dup
      end

      private

      def normalize_ext(ext)
        e = ext.to_s.downcase
        e.start_with?(".") ? e : ".#{e}"
      end
    end
  end
end

TavernKit::Ingest.register(".png", TavernKit::Ingest::Png)
TavernKit::Ingest.register(".apng", TavernKit::Ingest::Png)
TavernKit::Ingest.register(".byaf", TavernKit::Ingest::Byaf)
TavernKit::Ingest.register(".charx", TavernKit::Ingest::CharX)
