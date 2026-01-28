# frozen_string_literal: true

require "zlib"
require "base64"

module TavernKit
  module Png
    # Writes character card data to PNG files as tEXt chunks.
    #
    # Primary use case: embedding SillyTavern Character Card metadata
    # into PNG images (keywords: "chara" for V2, "ccv3" for V3).
    #
    # @example Embed character data into PNG
    #   TavernKit::Png::Writer.embed_character(
    #     "input.png",
    #     "output.png",
    #     character,
    #     format: :both
    #   )
    #
    module Writer
      PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b
      IEND_TYPE = "IEND".b
      TEXT_TYPE = "tEXt".b

      # Keywords for character card chunks
      V2_KEYWORD = "chara"
      V3_KEYWORD = "ccv3"

      # Valid format options
      VALID_FORMATS = %i[v2_only v3_only both].freeze

      module_function

      # Embed character data into a PNG file.
      #
      # Creates tEXt chunks containing base64-encoded JSON character data.
      # Existing character chunks (chara/ccv3) are removed before adding new ones.
      #
      # @param input_path [String] path to source PNG file
      # @param output_path [String] path to write output PNG file
      # @param character [Character] the character to embed
      # @param format [Symbol] :v2_only, :v3_only, or :both (default)
      # @return [void]
      # @raise [TavernKit::Png::WriteError] if writing fails
      # @raise [TavernKit::Png::ParseError] if input is not a valid PNG
      def embed_character(input_path, output_path, character, format: :both)
        validate_format!(format)

        # Read and validate PNG
        png_bytes = read_png_file(input_path)

        # Remove existing character chunks and get chunk positions
        chunks_data = parse_chunks(png_bytes)
        filtered_chunks = remove_character_chunks(chunks_data[:chunks])

        # Build new character chunks
        new_chunks = build_character_chunks(character, format)

        # Reconstruct PNG with new chunks inserted before IEND
        output_bytes = reconstruct_png(filtered_chunks, new_chunks)

        # Write output file
        write_png_file(output_path, output_bytes)
      end

      # Build a tEXt chunk with the given keyword and JSON payload.
      #
      # @param keyword [String] chunk keyword (e.g., "chara", "ccv3")
      # @param json_hash [Hash] data to encode as JSON
      # @return [String] raw chunk bytes (length + type + data + CRC)
      def build_text_chunk(keyword, json_hash)
        json_str = JSON.generate(json_hash)
        base64_data = Base64.strict_encode64(json_str)

        # tEXt data format: keyword + NUL + text
        chunk_data = "#{keyword}\x00#{base64_data}"

        build_chunk(TEXT_TYPE, chunk_data)
      end

      # @api private
      def validate_format!(format)
        return if VALID_FORMATS.include?(format)

        raise ArgumentError, "Invalid format: #{format.inspect}. Must be one of: #{VALID_FORMATS.join(', ')}"
      end

      # @api private
      def read_png_file(path)
        unless File.exist?(path)
          raise WriteError, "Input file not found: #{path}"
        end

        bytes = File.binread(path)

        unless bytes.start_with?(PNG_SIGNATURE)
          raise ParseError, "Invalid PNG signature in #{path}"
        end

        bytes
      end

      # @api private
      def write_png_file(path, bytes)
        File.binwrite(path, bytes)
      rescue SystemCallError => e
        raise WriteError, "Failed to write PNG file: #{e.message}"
      end

      # @api private
      # Parse PNG into chunks for manipulation.
      #
      # @param bytes [String] raw PNG bytes
      # @return [Hash] { signature:, chunks: [{type:, data:, raw:}, ...] }
      def parse_chunks(bytes)
        signature = bytes[0, 8]
        chunks = []
        pos = 8

        while pos < bytes.bytesize
          # Read chunk length (4 bytes, big-endian)
          length = bytes[pos, 4].unpack1("N")
          pos += 4

          # Read chunk type (4 bytes)
          type = bytes[pos, 4]
          pos += 4

          # Read chunk data
          data = bytes[pos, length]
          pos += length

          # Read CRC (4 bytes)
          crc = bytes[pos, 4]
          pos += 4

          # Store raw chunk for reconstruction
          raw = [length].pack("N") + type + data + crc

          chunks << { type: type, data: data, raw: raw }

          break if type == IEND_TYPE
        end

        { signature: signature, chunks: chunks }
      end

      # @api private
      # Remove existing character-related chunks (chara, ccv3).
      #
      # @param chunks [Array<Hash>] parsed chunks
      # @return [Array<Hash>] filtered chunks
      def remove_character_chunks(chunks)
        chunks.reject do |chunk|
          next false unless chunk[:type] == TEXT_TYPE

          # Check if keyword matches chara or ccv3
          keyword = extract_text_keyword(chunk[:data])
          [V2_KEYWORD, V3_KEYWORD].include?(keyword&.downcase)
        end
      end

      # @api private
      def extract_text_keyword(data)
        nul_pos = data.index("\x00")
        return nil if nul_pos.nil?

        data[0, nul_pos]
      end

      # @api private
      # Build character data chunks based on format.
      #
      # @param character [Character] character to embed
      # @param format [Symbol] :v2_only, :v3_only, or :both
      # @return [Array<String>] array of raw chunk bytes
      def build_character_chunks(character, format)
        chunks = []

        if format == :v2_only || format == :both
          v2_hash = CharacterCard.export_v2(character)
          chunks << build_text_chunk(V2_KEYWORD, v2_hash)
        end

        if format == :v3_only || format == :both
          v3_hash = CharacterCard.export_v3(character)
          chunks << build_text_chunk(V3_KEYWORD, v3_hash)
        end

        chunks
      end

      # @api private
      # Reconstruct PNG bytes with new chunks inserted before IEND.
      #
      # @param chunks [Array<Hash>] existing chunks (filtered)
      # @param new_chunks [Array<String>] new raw chunk bytes to insert
      # @return [String] complete PNG bytes
      def reconstruct_png(chunks, new_chunks)
        output = PNG_SIGNATURE.dup

        chunks.each do |chunk|
          if chunk[:type] == IEND_TYPE
            # Insert new chunks before IEND
            new_chunks.each { |nc| output << nc }
          end

          output << chunk[:raw]
        end

        output
      end

      # @api private
      # Build a raw PNG chunk.
      #
      # @param type [String] 4-byte chunk type
      # @param data [String] chunk data bytes
      # @return [String] raw chunk bytes (length + type + data + CRC)
      def build_chunk(type, data)
        # Length (4 bytes, big-endian)
        length_bytes = [data.bytesize].pack("N")

        # CRC is calculated over type + data
        crc_input = type + data
        crc = Zlib.crc32(crc_input)
        crc_bytes = [crc].pack("N")

        length_bytes + type + data + crc_bytes
      end
    end
  end
end
