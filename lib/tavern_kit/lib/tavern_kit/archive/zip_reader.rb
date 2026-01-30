# frozen_string_literal: true

require "zip"

module TavernKit
  module Archive
    # Small wrapper around rubyzip that enforces basic safety limits when
    # reading untrusted ZIP-based packaging formats (.byaf/.charx).
    #
    # This intentionally does NOT extract to disk; callers read specific entries
    # (usually JSON) and may optionally stream assets to the application layer.
    class ZipReader
      DEFAULT_MAX_ENTRIES = 2_000
      DEFAULT_MAX_ENTRY_BYTES = 10 * 1024 * 1024 # 10 MiB
      DEFAULT_MAX_TOTAL_BYTES = 50 * 1024 * 1024 # 50 MiB
      DEFAULT_MAX_JSON_BYTES = 2 * 1024 * 1024 # 2 MiB
      DEFAULT_MAX_COMPRESSION_RATIO = 200

      def self.open(source, **limits)
        raise ArgumentError, "block is required" unless block_given?

        zip = open_zip(source)
        reader = new(zip, **limits)

        yield reader
      rescue Zip::Error => e
        raise TavernKit::Archive::ZipError, e.message
      ensure
        zip&.close
      end

      def initialize(
        zip,
        max_entries: DEFAULT_MAX_ENTRIES,
        max_entry_bytes: DEFAULT_MAX_ENTRY_BYTES,
        max_total_bytes: DEFAULT_MAX_TOTAL_BYTES,
        max_json_bytes: DEFAULT_MAX_JSON_BYTES,
        max_compression_ratio: DEFAULT_MAX_COMPRESSION_RATIO,
        allow_encrypted: false
      )
        @zip = zip
        @max_entries = Integer(max_entries)
        @max_entry_bytes = Integer(max_entry_bytes)
        @max_total_bytes = Integer(max_total_bytes)
        @max_json_bytes = Integer(max_json_bytes)
        @max_compression_ratio = Integer(max_compression_ratio)
        @allow_encrypted = allow_encrypted == true

        @bytes_read = 0

        raise ArgumentError, "max_entries must be positive" if @max_entries <= 0
        raise ArgumentError, "max_entry_bytes must be positive" if @max_entry_bytes <= 0
        raise ArgumentError, "max_total_bytes must be positive" if @max_total_bytes <= 0
        raise ArgumentError, "max_json_bytes must be positive" if @max_json_bytes <= 0
        raise ArgumentError, "max_compression_ratio must be positive" if @max_compression_ratio <= 0

        validate_entry_count!
      end

      def entry?(path)
        !@zip.find_entry(path.to_s).nil?
      end

      def entries
        @zip.entries.map do |entry|
          validate_entry_name!(entry.name.to_s)
          entry.name
        end
      end

      def read(path, max_bytes: @max_entry_bytes)
        entry = fetch_entry(path)
        validate_entry!(entry)

        limit = Integer(max_bytes)
        raise ArgumentError, "max_bytes must be positive" if limit <= 0

        # Header sizes are untrusted; enforce a hard cap while reading.
        if entry.size && entry.size.to_i > limit
          raise TavernKit::Archive::ZipError, "Entry too large: #{entry.name.inspect} (#{entry.size} bytes)"
        end

        data = entry.get_input_stream.read(limit + 1)
        if data.bytesize > limit
          raise TavernKit::Archive::ZipError, "Entry too large: #{entry.name.inspect} (> #{limit} bytes)"
        end

        consume_budget!(data.bytesize)
        data
      end

      def read_json(path, max_bytes: @max_json_bytes)
        raw = read(path, max_bytes: max_bytes)
        JSON.parse(raw)
      rescue JSON::ParserError => e
        raise TavernKit::Archive::ZipError, "#{path.inspect} is not valid JSON (#{e.message})"
      end

      private

      def self.open_zip(source)
        if source.is_a?(String)
          begin
            return Zip::File.open(source) if File.file?(source)
          rescue ArgumentError
            # Binary strings (ZIP bytes) can contain null bytes and are not valid paths.
          end
        end

        Zip::File.open_buffer(source)
      end

      def validate_entry_count!
        count = @zip.entries.size
        return if count <= @max_entries

        raise TavernKit::Archive::ZipError, "Too many ZIP entries: #{count} (max: #{@max_entries})"
      end

      def fetch_entry(path)
        name = path.to_s
        entry = @zip.find_entry(name)
        raise TavernKit::Archive::ZipError, "Missing ZIP entry: #{name.inspect}" unless entry

        entry
      end

      def validate_entry!(entry)
        name = entry.name.to_s

        validate_entry_name!(name)

        if entry.encrypted? && !@allow_encrypted
          raise TavernKit::Archive::ZipError, "Encrypted ZIP entries are not supported: #{name.inspect}"
        end

        if entry.size && entry.size.to_i > @max_entry_bytes
          raise TavernKit::Archive::ZipError, "Entry too large: #{name.inspect} (#{entry.size} bytes)"
        end

        if entry.size && entry.compressed_size && entry.compressed_size.to_i.positive?
          ratio = entry.size.to_f / entry.compressed_size.to_f
          if ratio > @max_compression_ratio
            raise TavernKit::Archive::ZipError,
              format("ZIP entry compression ratio too high: %<name>s (%<ratio>.1f)", name: name.inspect, ratio: ratio)
          end
        end

        nil
      end

      def validate_entry_name!(name)
        if name.bytesize > 1024
          raise TavernKit::Archive::ZipError, "ZIP entry name too long: #{name.bytesize} bytes"
        end

        if name.start_with?("/") || name.match?(%r{\A[A-Za-z]:[/\\]})
          raise TavernKit::Archive::ZipError, "ZIP entry path must be relative: #{name.inspect}"
        end

        if name.include?("\\") || name.include?("\0")
          raise TavernKit::Archive::ZipError, "ZIP entry path is invalid: #{name.inspect}"
        end

        parts = name.split("/")
        if parts.any? { |p| p == ".." }
          raise TavernKit::Archive::ZipError, "ZIP entry path traversal is not allowed: #{name.inspect}"
        end

        nil
      end

      def consume_budget!(bytes)
        @bytes_read += Integer(bytes)
        return if @bytes_read <= @max_total_bytes

        raise TavernKit::Archive::ZipError, "ZIP read budget exceeded: #{@bytes_read} bytes (max: #{@max_total_bytes})"
      end
    end
  end
end
