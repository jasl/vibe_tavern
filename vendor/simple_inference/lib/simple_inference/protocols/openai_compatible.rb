# frozen_string_literal: true

require "json"
require "securerandom"
require "uri"
require "timeout"
require "socket"

require_relative "base"

module SimpleInference
  module Protocols
    # OpenAI-compatible HTTP API protocol implementation.
    #
    # This class implements the currently supported API surface in SimpleInference:
    # - /chat/completions (including SSE streaming)
    # - /embeddings
    # - /rerank
    # - /models
    # - /health
    # - /audio/* (multipart)
    #
    # Future protocols (Anthropic, Gemini, etc.) should live alongside this class
    # under `SimpleInference::Protocols::*`, keeping provider-specific request/response
    # shapes out of shared application code.
    class OpenAICompatible < Base
      # POST /v1/chat/completions
      # params: { model: "model-name", messages: [...], ... }
      def chat_completions(**params)
        post_json(api_path("/chat/completions"), params)
      end

      # High-level helper for OpenAI-compatible chat.
      #
      # - Non-streaming: returns an OpenAI::ChatResult with `content` + `usage`.
      # - Streaming: yields delta strings to the block (if given), accumulates, and returns OpenAI::ChatResult.
      #
      # @param model [String]
      # @param messages [Array<Hash>]
      # @param stream [Boolean] force streaming when true (default: block_given?)
      # @param include_usage [Boolean, nil] when true (and streaming), requests usage in the final chunk
      # @param request_logprobs [Boolean] when true, requests logprobs (and collects them in streaming mode)
      # @param top_logprobs [Integer, nil] default: 5 (when request_logprobs is true)
      # @param params [Hash] additional OpenAI parameters (max_tokens, temperature, etc.)
      # @yield [String] delta content chunks (streaming only)
      # @return [SimpleInference::OpenAI::ChatResult]
      def chat(model:, messages:, stream: nil, include_usage: nil, request_logprobs: false, top_logprobs: 5, **params, &block)
        raise ArgumentError, "model is required" if model.nil? || model.to_s.strip.empty?
        raise ArgumentError, "messages must be an Array" unless messages.is_a?(Array)

        use_stream = stream.nil? ? block_given? : stream

        request = { model: model, messages: messages }.merge(params)
        request.delete(:stream)
        request.delete("stream")

        if request_logprobs
          request[:logprobs] = true unless request.key?(:logprobs) || request.key?("logprobs")
          if top_logprobs && !(request.key?(:top_logprobs) || request.key?("top_logprobs"))
            request[:top_logprobs] = top_logprobs
          end
        end

        if use_stream && include_usage
          stream_options = request[:stream_options] || request["stream_options"]
          stream_options ||= {}

          if stream_options.is_a?(Hash)
            stream_options[:include_usage] = true unless stream_options.key?(:include_usage) || stream_options.key?("include_usage")
          end

          request[:stream_options] = stream_options
        end

        if use_stream
          full = +""
          finish_reason = nil
          last_usage = nil
          collected_logprobs = []

          response =
            chat_completions_stream(**request) do |event|
              delta = OpenAI.chat_completion_chunk_delta(event)
              if delta
                full << delta
                block.call(delta) if block
              end

              fr = event.is_a?(Hash) ? event.dig("choices", 0, "finish_reason") : nil
              finish_reason = fr if fr

              if request_logprobs
                chunk_logprobs = event.is_a?(Hash) ? event.dig("choices", 0, "logprobs", "content") : nil
                if chunk_logprobs.is_a?(Array)
                  collected_logprobs.concat(chunk_logprobs)
                end
              end

              usage = OpenAI.chat_completion_usage(event)
              last_usage = usage if usage
            end

          OpenAI::ChatResult.new(
            content: full,
            usage: last_usage || OpenAI.chat_completion_usage(response),
            finish_reason: finish_reason || OpenAI.chat_completion_finish_reason(response),
            logprobs: collected_logprobs.empty? ? OpenAI.chat_completion_logprobs(response) : collected_logprobs,
            response: response
          )
        else
          response = chat_completions(**request)
          OpenAI::ChatResult.new(
            content: OpenAI.chat_completion_content(response),
            usage: OpenAI.chat_completion_usage(response),
            finish_reason: OpenAI.chat_completion_finish_reason(response),
            logprobs: OpenAI.chat_completion_logprobs(response),
            response: response
          )
        end
      end

      # Streaming chat as an Enumerable.
      #
      # @return [SimpleInference::OpenAI::ChatStream]
      def chat_stream(model:, messages:, include_usage: nil, request_logprobs: false, top_logprobs: 5, **params)
        OpenAI::ChatStream.new(
          client: self,
          model: model,
          messages: messages,
          include_usage: include_usage,
          request_logprobs: request_logprobs,
          top_logprobs: top_logprobs,
          params: params
        )
      end

      # POST /v1/chat/completions (streaming)
      #
      # Yields parsed JSON events from an OpenAI-style SSE stream (`text/event-stream`).
      #
      # If no block is given, returns an Enumerator.
      def chat_completions_stream(**params)
        return enum_for(:chat_completions_stream, **params) unless block_given?

        body = params.dup
        body.delete(:stream)
        body.delete("stream")
        body["stream"] = true

        response = post_json_stream(api_path("/chat/completions"), body) do |event|
          yield event
        end

        content_type = response.headers["content-type"].to_s

        # Streaming case: we already yielded events from the SSE stream.
        if response.status >= 200 && response.status < 300 && content_type.include?("text/event-stream")
          return response
        end

        # Fallback when upstream does not support streaming (this repo's server).
        if streaming_unsupported_error?(response.status, response.body)
          fallback_body = params.dup
          fallback_body.delete(:stream)
          fallback_body.delete("stream")

          fallback_response = post_json(api_path("/chat/completions"), fallback_body)
          chunk = synthesize_chat_completion_chunk(fallback_response.body)
          yield chunk if chunk
          return fallback_response
        end

        # If we got a non-streaming success response (JSON), convert it into a single
        # chunk so streaming consumers can share the same code path.
        if response.status >= 200 && response.status < 300
          chunk = synthesize_chat_completion_chunk(response.body)
          yield chunk if chunk
        end

        response
      end

      # POST /v1/embeddings
      def embeddings(**params)
        post_json(api_path("/embeddings"), params)
      end

      # POST /v1/rerank
      def rerank(**params)
        post_json(api_path("/rerank"), params)
      end

      # GET /v1/models
      def list_models
        get_json(api_path("/models"))
      end

      # Convenience wrapper for list_models.
      #
      # @return [Array<String>] model IDs
      def models
        response = list_models
        data = response.body.is_a?(Hash) ? response.body["data"] : nil
        Array(data).filter_map { |m| m.is_a?(Hash) ? m["id"] : nil }
      end

      # GET /health
      def health
        get_json("/health")
      end

      # Returns true when service is healthy, false otherwise.
      def healthy?
        response = get_json("/health", raise_on_http_error: false)
        status_ok = response.status == 200
        body_status_ok = response.body.is_a?(Hash) && response.body["status"] == "ok"
        status_ok && body_status_ok
      rescue Errors::Error
        false
      end

      # POST /v1/audio/transcriptions
      # params: { file: io_or_hash, model: "model-name", **audio_options }
      def audio_transcriptions(**params)
        post_multipart(api_path("/audio/transcriptions"), params)
      end

      # POST /v1/audio/translations
      def audio_translations(**params)
        post_multipart(api_path("/audio/translations"), params)
      end

      private

      def base_url
        config.base_url
      end

      def api_path(endpoint)
        "#{config.api_prefix}#{endpoint}"
      end

      def get_json(path, params: nil, raise_on_http_error: nil)
        full_path = with_query(path, params)
        request_json(
          method: :get,
          url: "#{base_url}#{full_path}",
          headers: config.headers,
          body: nil,
          expect_json: true,
          raise_on_http_error: raise_on_http_error,
        )
      end

      def post_json(path, body, raise_on_http_error: nil)
        request_json(
          method: :post,
          url: "#{base_url}#{path}",
          headers: config.headers,
          body: body,
          expect_json: true,
          raise_on_http_error: raise_on_http_error,
        )
      end

      def post_json_stream(path, body, raise_on_http_error: nil, &on_event)
        if base_url.nil? || base_url.empty?
          raise Errors::ConfigurationError, "base_url is required"
        end

        url = "#{base_url}#{path}"
        validate_url!(url)

        headers = config.headers.merge(
          "Content-Type" => "application/json",
          "Accept" => "text/event-stream, application/json"
        )
        payload = body.nil? ? nil : JSON.generate(body)

        request_env = {
          method: :post,
          url: url,
          headers: headers,
          body: payload,
          timeout: config.timeout,
          open_timeout: config.open_timeout,
          read_timeout: config.read_timeout,
        }

        handle_stream_response(request_env, raise_on_http_error: raise_on_http_error, &on_event)
      end

      def handle_stream_response(request_env, raise_on_http_error:, &on_event)
        sse_buffer = +""
        sse_done = false
        streamed = false

        raw_response =
          @adapter.call_stream(request_env) do |chunk|
            streamed = true
            next if sse_done

            sse_buffer << chunk.to_s
            sse_done = consume_sse_buffer!(sse_buffer, &on_event) || sse_done
          end

        status = raw_response[:status]
        headers = (raw_response[:headers] || {}).transform_keys { |k| k.to_s.downcase }
        body = raw_response[:body]
        body_str = body.nil? ? "" : body.to_s

        content_type = headers["content-type"].to_s

        # Streaming case.
        if status >= 200 && status < 300 && content_type.include?("text/event-stream")
          # If we couldn't stream incrementally, best-effort parse the full SSE body.
          unless streamed
            buffer = body_str.dup
            consume_sse_buffer!(buffer, &on_event)
          end

          return Response.new(status: status, headers: headers, body: nil)
        end

        # Non-streaming response path (adapter doesn't support streaming or server returned JSON).
        should_parse_json = content_type.include?("json")
        parsed_body =
          if should_parse_json
            begin
              parse_json(body_str)
            rescue Errors::DecodeError
              # Prefer HTTPError over DecodeError for non-2xx responses.
              status >= 200 && status < 300 ? raise : body_str
            end
          else
            body_str
          end

        response = Response.new(status: status, headers: headers, body: parsed_body, raw_body: body_str)
        maybe_raise_http_error(response: response, raise_on_http_error: raise_on_http_error, ignore_streaming_unsupported: true)
        response
      rescue Timeout::Error => e
        raise Errors::TimeoutError, e.message
      rescue SocketError, SystemCallError => e
        raise Errors::ConnectionError, e.message
      end

      def extract_sse_blocks!(buffer)
        blocks = []

        loop do
          idx_lf = buffer.index("\n\n")
          idx_crlf = buffer.index("\r\n\r\n")

          idx = [idx_lf, idx_crlf].compact.min
          break if idx.nil?

          sep_len = (idx == idx_crlf) ? 4 : 2
          blocks << buffer.slice!(0, idx)
          buffer.slice!(0, sep_len)
        end

        blocks
      end

      def consume_sse_buffer!(buffer, &on_event)
        done = false

        extract_sse_blocks!(buffer).each do |block|
          data = sse_data_from_block(block)
          next if data.nil?

          payload = data.strip
          next if payload.empty?
          if payload == "[DONE]"
            done = true
            buffer.clear
            break
          end

          on_event&.call(parse_json_event(payload))
        end

        done
      end

      def sse_data_from_block(block)
        return nil if block.nil? || block.empty?

        data_lines = []
        block.split(/\r?\n/).each do |line|
          next if line.nil? || line.empty?
          next if line.start_with?(":")
          next unless line.start_with?("data:")

          data_lines << (line[5..]&.lstrip).to_s
        end

        return nil if data_lines.empty?

        data_lines.join("\n")
      end

      def parse_json_event(payload)
        JSON.parse(payload)
      rescue JSON::ParserError => e
        raise Errors::DecodeError, "Failed to parse SSE JSON event: #{e.message}"
      end

      def streaming_unsupported_error?(status, body)
        return false unless status.to_i == 400
        return false unless body.is_a?(Hash)

        body["detail"].to_s.strip == "Streaming responses are not supported yet"
      end

      def synthesize_chat_completion_chunk(body)
        return nil unless body.is_a?(Hash)

        id = body["id"]
        created = body["created"]
        model = body["model"]

        choices = body["choices"]
        return nil unless choices.is_a?(Array) && !choices.empty?

        choice0 = choices[0]
        return nil unless choice0.is_a?(Hash)

        message = choice0["message"]
        return nil unless message.is_a?(Hash)

        role = message["role"] || "assistant"
        content = message["content"]

        {
          "id" => id,
          "object" => "chat.completion.chunk",
          "created" => created,
          "model" => model,
          "choices" => [
            {
              "index" => choice0["index"] || 0,
              "delta" => {
                "role" => role,
                "content" => content,
              },
              "finish_reason" => choice0["finish_reason"],
            },
          ],
        }
      end

      def with_query(path, params)
        return path if params.nil? || params.empty?

        query = URI.encode_www_form(params)
        separator = path.include?("?") ? "&" : "?"
        "#{path}#{separator}#{query}"
      end

      def post_multipart(path, params)
        file_value = params[:file] || params["file"]
        model = params[:model] || params["model"]

        raise Errors::ConfigurationError, "file is required" if file_value.nil?
        raise Errors::ConfigurationError, "model is required" if model.nil? || model.to_s.empty?

        io, filename = normalize_upload(file_value)

        form_fields = {
          "model" => model.to_s,
        }

        # Optional scalar fields
        %i[language prompt response_format temperature].each do |key|
          value = params[key] || params[key.to_s]
          next if value.nil?

          form_fields[key.to_s] = value.to_s
        end

        # timestamp_granularities can be an array or single value
        tgs = params[:timestamp_granularities] || params["timestamp_granularities"]
        if tgs && !tgs.empty?
          Array(tgs).each_with_index do |value, index|
            form_fields["timestamp_granularities[#{index}]"] = value.to_s
          end
        end

        body, headers = build_multipart_body(io, filename, form_fields)
        headers["Transfer-Encoding"] = "chunked" if body.respond_to?(:size) && body.size.nil?

        request_env = {
          method: :post,
          url: "#{base_url}#{path}",
          headers: config.headers.merge(headers),
          body: body,
          timeout: config.timeout,
          open_timeout: config.open_timeout,
          read_timeout: config.read_timeout,
        }

        handle_response(
          request_env,
          expect_json: nil, # auto-detect based on Content-Type
          raise_on_http_error: nil
        )
      ensure
        if io && io.respond_to?(:close)
          begin
            io.close unless io.closed?
          rescue StandardError
            # ignore close errors
          end
        end
      end

      def normalize_upload(file)
        if file.is_a?(Hash)
          io = file[:io] || file["io"]
          filename = file[:filename] || file["filename"] || "audio.wav"
        elsif file.respond_to?(:read)
          io = file
          filename =
            if file.respond_to?(:path) && file.path
              File.basename(file.path)
            else
              "audio.wav"
            end
        else
          raise Errors::ConfigurationError,
                "file must be an IO object or a hash with :io and :filename keys"
        end

        raise Errors::ConfigurationError, "file IO is required" if io.nil?

        [io, filename]
      end

      def build_multipart_body(io, filename, fields)
        boundary = "simple-inference-ruby-#{SecureRandom.hex(12)}"

        headers = {
          "Content-Type" => "multipart/form-data; boundary=#{boundary}",
        }

        parts = []
        fields.each do |name, value|
          parts << "--#{boundary}\r\n".b
          parts << %(Content-Disposition: form-data; name="#{name}"\r\n\r\n).b
          parts << value.to_s.b
          parts << "\r\n".b
        end

        parts << "--#{boundary}\r\n".b
        parts << %(Content-Disposition: form-data; name="file"; filename="#{filename}"\r\n).b
        parts << "Content-Type: application/octet-stream\r\n\r\n".b
        parts << io
        parts << "\r\n--#{boundary}--\r\n".b

        [MultipartStream.new(parts), headers]
      end

      class MultipartStream
        def initialize(parts)
          @parts = parts
          @part_index = 0
          @string_offset = 0
          @size = nil
        end

        def read(length = nil, outbuf = nil)
          return "".b if length.nil? && eof?
          return nil if eof?

          out = outbuf ? outbuf.replace("".b) : +"".b

          if length.nil?
            while (chunk = read(16_384))
              out << chunk
            end
            return out
          end

          while out.bytesize < length && !eof?
            part = @parts.fetch(@part_index)

            if part.is_a?(String)
              remaining = part.bytesize - @string_offset
              if remaining <= 0
                advance_part!
                next
              end

              take = [length - out.bytesize, remaining].min
              out << part.byteslice(@string_offset, take)
              @string_offset += take

              advance_part! if @string_offset >= part.bytesize
            else
              chunk = part.read(length - out.bytesize)
              if chunk.nil? || chunk.empty?
                advance_part!
                next
              end

              out << chunk
            end
          end

          return nil if out.empty? && eof?

          out
        end

        def size
          @size ||= compute_size
        end

        private

        def eof?
          @part_index >= @parts.length
        end

        def advance_part!
          @part_index += 1
          @string_offset = 0
        end

        def compute_size
          total = 0

          @parts.each do |part|
            if part.is_a?(String)
              total += part.bytesize
              next
            end

            return nil unless part.respond_to?(:size)

            part_size = part.size
            if part.respond_to?(:pos)
              begin
                part_size -= part.pos
              rescue StandardError
                # ignore pos errors
              end
            end

            total += part_size
          end

          total
        end
      end
    end
  end
end
