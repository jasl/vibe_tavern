# frozen_string_literal: true

require "zlib"
require "base64"

module TavernKit
  module Png
    # Extracts text chunks (tEXt, zTXt, iTXt) from PNG/APNG files.
    #
    # Primary use case: extracting SillyTavern Character Card metadata
    # embedded in PNG images (keywords: "chara", "ccv3").
    #
    # @example Extract card data from PNG
    #   payload = TavernKit::Png::Parser.extract_card_payload("card.png")
    #   # => { "spec" => "chara_card_v2", "data" => { ... } }
    #
    module Parser
      PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b
      CARD_KEYWORDS = %w[ccv3 chara].freeze
      TEXT_CHUNK_TYPES = %w[tEXt zTXt iTXt].freeze

      # Safety limits: PNGs can have large IDAT chunks (image bytes). We avoid
      # loading non-text chunks into memory and only bound metadata text chunks.
      DEFAULT_MAX_TEXT_CHUNK_BYTES = 5 * 1024 * 1024 # 5 MiB
      DEFAULT_MAX_INFLATED_TEXT_BYTES = 2 * 1024 * 1024 # 2 MiB

      module_function

      # Extract all text chunks from a PNG file.
      #
      # @param path [String] path to PNG file
      # @return [Array<Hash>] array of { keyword:, text:, chunk: } hashes
      # @raise [TavernKit::Png::ParseError] if file is not a valid PNG
      def extract_text_chunks(path, max_text_chunk_bytes: DEFAULT_MAX_TEXT_CHUNK_BYTES, max_inflated_text_bytes: DEFAULT_MAX_INFLATED_TEXT_BYTES)
        chunks = []

        File.open(path, "rb") do |f|
          file_size = File.size(path).to_i
          sig = f.read(8)
          unless sig == PNG_SIGNATURE
            raise ParseError, "Invalid PNG signature in #{path}"
          end

          loop do
            len = read_uint32_be(f)
            break if len.nil?

            type = f.read(4)
            if type.nil? || type.bytesize < 4
              raise ParseError, "Truncated chunk type in #{path}"
            end

            # Ensure the file has enough bytes remaining for this chunk payload + CRC.
            if f.pos + len.to_i + 4 > file_size
              raise ParseError, "Truncated chunk data for #{type} in #{path}"
            end

            if TEXT_CHUNK_TYPES.include?(type)
              limit = Integer(max_text_chunk_bytes)
              raise ArgumentError, "max_text_chunk_bytes must be positive" if limit <= 0
              raise ParseError, "Text chunk too large: #{type} (#{len} bytes)" if len.to_i > limit

              data = f.read(len)
              if data.nil? || data.bytesize < len
                raise ParseError, "Truncated chunk data for #{type} in #{path}"
              end

              _crc = f.read(4) # Skip CRC validation

              case type
              when "tEXt"
                entry = decode_text(data)
                chunks << entry if entry
              when "zTXt"
                entry = decode_ztxt(data, max_inflated_text_bytes: max_inflated_text_bytes)
                chunks << entry if entry
              when "iTXt"
                entry = decode_itxt(data, max_inflated_text_bytes: max_inflated_text_bytes)
                chunks << entry if entry
              end
            else
              # Skip non-text chunk payload + CRC without loading into memory.
              f.seek(len.to_i + 4, IO::SEEK_CUR)
            end

            break if type == "IEND"
          end
        end

        chunks
      end

      # Extract and decode character card payload from PNG.
      #
      # Looks for "ccv3" or "chara" keywords, decodes base64, parses JSON.
      #
      # @param path [String] path to PNG file
      # @return [Hash] parsed JSON card data
      # @raise [TavernKit::Png::ParseError] if no card found or parse fails
      def extract_card_payload(path, **limits)
        chunks = extract_text_chunks(path, **limits)
        chosen = pick_card_chunk(chunks)

        if chosen.nil?
          raise ParseError, "No character metadata found in #{path} (expected keyword 'ccv3' or 'chara')"
        end

        raw = chosen[:text].to_s
        parsed = decode_card_json(raw)

        if parsed.nil?
          raise ParseError, "Could not parse card JSON from #{path} (keyword=#{chosen[:keyword]})"
        end

        parsed
      end

      # @api private
      def read_uint32_be(io)
        bytes = io.read(4)
        return nil if bytes.nil? || bytes.bytesize < 4

        bytes.unpack1("N")
      end

      # @api private
      def safe_utf8(str)
        return "" if str.nil?

        str.force_encoding("UTF-8")
        str.encode("UTF-8", invalid: :replace, undef: :replace, replace: "\uFFFD")
      end

      # @api private
      def split_cstring(bytes, start_idx = 0)
        nul = bytes.index("\x00", start_idx)
        return [nil, nil] if nul.nil?

        [bytes[start_idx...nul], nul + 1]
      end

      # @api private
      def decode_text(data)
        key_bytes, idx = split_cstring(data, 0)
        return nil if key_bytes.nil?

        keyword = safe_utf8(key_bytes)
        text = safe_utf8(data[idx..] || "".b)
        { keyword: keyword, text: text, chunk: "tEXt" }
      end

      # @api private
      def decode_ztxt(data, max_inflated_text_bytes: DEFAULT_MAX_INFLATED_TEXT_BYTES)
        key_bytes, idx = split_cstring(data, 0)
        return nil if key_bytes.nil?

        keyword = safe_utf8(key_bytes)
        return nil if idx >= data.bytesize

        compression_method = data.getbyte(idx)
        idx += 1
        return nil unless compression_method == 0 # deflate

        compressed = data[idx..] || "".b
        text = inflate_limited(compressed, max_bytes: max_inflated_text_bytes)

        { keyword: keyword, text: safe_utf8(text), chunk: "zTXt" }
      rescue Zlib::DataError
        nil
      end

      # @api private
      def decode_itxt(data, max_inflated_text_bytes: DEFAULT_MAX_INFLATED_TEXT_BYTES)
        key_bytes, idx = split_cstring(data, 0)
        return nil if key_bytes.nil?

        keyword = safe_utf8(key_bytes)
        return nil if idx + 2 > data.bytesize

        compression_flag = data.getbyte(idx)
        compression_method = data.getbyte(idx + 1)
        idx += 2

        # Skip language tag
        _lang_bytes, idx = split_cstring(data, idx)
        return nil if idx.nil?

        # Skip translated keyword
        _translated_bytes, idx = split_cstring(data, idx)
        return nil if idx.nil?

        text_bytes = data[idx..] || "".b

        if compression_flag == 1
          return nil unless compression_method == 0

          text_bytes = inflate_limited(text_bytes, max_bytes: max_inflated_text_bytes)
        end

        { keyword: keyword, text: safe_utf8(text_bytes), chunk: "iTXt" }
      rescue Zlib::DataError
        nil
      end

      # Inflate a deflate-compressed string with a hard output size cap.
      #
      # Uses incremental feeding to keep intermediate allocations bounded.
      def inflate_limited(compressed, max_bytes:)
        limit = Integer(max_bytes)
        raise ArgumentError, "max_inflated_text_bytes must be positive" if limit <= 0

        inflater = Zlib::Inflate.new
        out = +""

        # Small-ish input chunk size helps keep intermediate output chunks small
        # even for very high compression ratios.
        chunk_size = 1024
        idx = 0
        bytes = compressed.to_s.b

        while idx < bytes.bytesize
          piece = bytes.byteslice(idx, chunk_size)
          idx += chunk_size

          produced = inflater.inflate(piece)
          out << produced unless produced.empty?

          raise ParseError, "Inflated text chunk too large (> #{limit} bytes)" if out.bytesize > limit
        end

        tail = inflater.finish
        out << tail unless tail.empty?
        raise ParseError, "Inflated text chunk too large (> #{limit} bytes)" if out.bytesize > limit

        out
      ensure
        inflater&.close
      end

      # @api private
      def pick_card_chunk(chunks)
        by_key = Hash.new { |h, k| h[k] = [] }
        chunks.each do |c|
          k = c[:keyword].to_s.downcase
          by_key[k] << c
        end

        # Prefer ccv3 over chara
        CARD_KEYWORDS.each do |key|
          return by_key[key].last unless by_key[key].empty?
        end

        nil
      end

      # @api private
      def decode_card_json(raw)
        # Most cards are base64(JSON). Some tools may store plain JSON.
        parsed = nil

        # Try base64 -> JSON first
        begin
          compact = raw.gsub(/\s+/, "")
          decoded = Base64.strict_decode64(compact)
          decoded = safe_utf8(decoded)
          parsed = JSON.parse(decoded)
        rescue ArgumentError, JSON::ParserError
          # Try lenient base64
          begin
            decoded = Base64.decode64(raw.gsub(/\s+/, ""))
            decoded = safe_utf8(decoded)
            parsed = JSON.parse(decoded)
          rescue JSON::ParserError
            parsed = nil
          end
        end

        # Fallback: raw text might already be JSON
        parsed ||= begin
          JSON.parse(raw)
        rescue JSON::ParserError
          nil
        end

        parsed
      end
    end
  end
end
