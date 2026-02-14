# frozen_string_literal: true

require "json"

module AgentCore
  module MCP
    module Transport
      # HTTP transport for MCP servers using Streamable HTTP (SSE).
      #
      # Sends JSON-RPC messages via HTTP POST and receives responses
      # as SSE (Server-Sent Events) streams or plain JSON. Manages
      # session lifecycle, reconnection, and cancellation.
      #
      # Requires the httpx gem at runtime. Users who need this transport
      # must add httpx to their Gemfile. The gem is lazy-loaded when
      # this class is first used.
      #
      # Thread-safe: uses a Mutex + ConditionVariable for queue management.
      # One background worker thread processes outbound messages sequentially.
      class StreamableHttp < Base
        DEFAULT_SSE_MAX_RECONNECTS = 20
        DEFAULT_SSE_MAX_BUFFER_BYTES = 1_000_000
        DEFAULT_MAX_RESPONSE_BYTES = 8 * 1024 * 1024

        Token = Struct.new(:cancelled, :reason, keyword_init: true)
        Job = Data.define(:message, :id, :method, :token, :dynamic_headers)

        class BodyTooLargeError < StandardError; end
        class InvalidSseEventDataError < StandardError; end

        attr_reader :session_id

        # @param url [String] The MCP server URL
        # @param headers [Hash, nil] Static HTTP headers
        # @param headers_provider [#call, nil] Dynamic header callback
        # @param timeout_s [Float] General request timeout
        # @param open_timeout_s [Float, nil] Connection timeout
        # @param read_timeout_s [Float, nil] Read timeout
        # @param sse_max_reconnects [Integer, nil] Max SSE reconnect attempts
        # @param max_response_bytes [Integer, nil] Max response body size
        # @param sleep_fn [#call, nil] Sleep function for testing
        # @param http_client [Object, nil] Injected HTTP client (for testing)
        # @param on_stdout_line [#call, nil] Callback for parsed messages
        # @param on_stderr_line [#call, nil] Callback for debug/error output
        def initialize(
          url:,
          headers: nil,
          headers_provider: nil,
          timeout_s: AgentCore::MCP::DEFAULT_TIMEOUT_S,
          open_timeout_s: nil,
          read_timeout_s: nil,
          sse_max_reconnects: nil,
          max_response_bytes: nil,
          sleep_fn: nil,
          http_client: nil,
          on_stdout_line: nil,
          on_stderr_line: nil
        )
          @url = url.to_s.strip
          raise ArgumentError, "url is required" if @url.empty?

          @headers = normalize_headers(headers)
          @headers_provider = normalize_headers_provider(headers_provider)

          @timeout_s = Float(timeout_s)
          raise ArgumentError, "timeout_s must be positive" if @timeout_s <= 0

          @open_timeout_s = open_timeout_s.nil? ? @timeout_s : Float(open_timeout_s)
          raise ArgumentError, "open_timeout_s must be positive" if @open_timeout_s <= 0

          @read_timeout_s = read_timeout_s.nil? ? @timeout_s : Float(read_timeout_s)
          raise ArgumentError, "read_timeout_s must be positive" if @read_timeout_s <= 0

          @sse_max_reconnects =
            sse_max_reconnects.nil? ? DEFAULT_SSE_MAX_RECONNECTS : Integer(sse_max_reconnects)
          raise ArgumentError, "sse_max_reconnects must be positive" if @sse_max_reconnects <= 0

          @max_response_bytes =
            max_response_bytes.nil? ? DEFAULT_MAX_RESPONSE_BYTES : Integer(max_response_bytes)
          raise ArgumentError, "max_response_bytes must be positive" if @max_response_bytes <= 0

          @sleep_fn = sleep_fn&.respond_to?(:call) ? sleep_fn : Kernel.method(:sleep)
          @http_client = http_client

          @on_stdout_line = on_stdout_line
          @on_stderr_line = on_stderr_line

          @mutex = Mutex.new
          @cv = ConditionVariable.new

          @started = false
          @closed = false
          @worker = nil

          @queue = []
          @inflight = {}

          @protocol_version = nil
          @session_id = nil

          @client = nil
          @stream_client = nil
          @sse_stream_client = nil

          @sse_thread = nil
          @sse_stop = false
          @sse_response = nil
          @sse_session_id = nil
        end

        def protocol_version=(value)
          s = value.to_s.strip
          s = nil if s.empty?

          should_start = false

          @mutex.synchronize do
            @protocol_version = s
            should_start = should_start_sse_stream_unsafe?
          end

          maybe_start_sse_stream! if should_start
        end

        def start
          @mutex.synchronize do
            raise AgentCore::MCP::ClosedError, "transport is closed" if @closed
            return self if @started

            build_http_clients!

            @worker = Thread.new { worker_loop }
            @started = true
          end

          maybe_start_sse_stream!

          self
        end

        def send_message(hash)
          message = hash.is_a?(Hash) ? hash : {}
          id = message.fetch("id", nil)
          method_name = message.fetch("method", "").to_s

          @mutex.synchronize do
            raise AgentCore::MCP::ClosedError, "transport is closed" if @closed
            raise AgentCore::MCP::TransportError, "transport is not started" unless @started
          end

          dynamic_headers = resolve_headers_provider!

          @mutex.synchronize do
            raise AgentCore::MCP::ClosedError, "transport is closed" if @closed
            raise AgentCore::MCP::TransportError, "transport is not started" unless @started

            token = nil
            unless id.nil?
              raise AgentCore::MCP::TransportError, "duplicate request id: #{id}" if @inflight.key?(id)

              token = Token.new(cancelled: false, reason: nil)
              @inflight[id] = token
            end

            job = Job.new(message: message, id: id, method: method_name, token: token, dynamic_headers: dynamic_headers)
            @queue << job
            @cv.signal
          end

          true
        end

        def cancel_request(request_id, reason: nil)
          token = nil
          session_id = nil
          protocol_version = nil

          @mutex.synchronize do
            token = @inflight[request_id]
            return false unless token

            token.cancelled = true
            token.reason = reason.to_s unless reason.nil?

            @queue.delete_if { |job| job.id == request_id }
            @inflight.delete(request_id)

            session_id = @session_id
            protocol_version = @protocol_version
          end

          if protocol_version && !protocol_version.to_s.strip.empty?
            Thread.new do
              send_cancel_notification(request_id, reason: reason, session_id: session_id, protocol_version: protocol_version)
            rescue StandardError
              nil
            end
          end

          true
        rescue StandardError
          false
        end

        def close(timeout_s: 2.0)
          timeout_s = Float(timeout_s)
          raise ArgumentError, "timeout_s must be positive" if timeout_s <= 0

          worker = nil
          sse_thread = nil
          sse_response = nil
          protocol_version = nil
          session_id = nil
          client = nil
          stream_client = nil
          sse_stream_client = nil

          @mutex.synchronize do
            return nil if @closed

            @closed = true
            @sse_stop = true

            worker = @worker
            @worker = nil

            sse_thread = @sse_thread
            @sse_thread = nil

            sse_response = @sse_response
            @sse_response = nil
            @sse_session_id = nil

            @queue.clear
            @inflight.clear

            protocol_version = @protocol_version
            session_id = @session_id

            client = @client
            stream_client = @stream_client
            sse_stream_client = @sse_stream_client

            @cv.broadcast
          end

          safe_close_response(sse_response)
          sse_thread&.join(0.2)
          if sse_thread&.alive?
            safe_close_client(sse_stream_client)
            sse_stream_client = nil

            sse_thread.kill
            sse_thread.join(0.1)
          end

          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_s
          grace_s = [0.2, timeout_s].min

          worker&.join(grace_s)

          if worker&.alive?
            safe_close_client(stream_client)
            safe_close_client(client)
            stream_client = nil
            client = nil

            remaining_s = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            worker.join(remaining_s) if remaining_s.positive?

            if worker.alive?
              worker.kill
              worker.join(0.1)
            end
          elsif session_id && protocol_version && !protocol_version.to_s.strip.empty?
            remaining_s = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            if remaining_s.positive?
              deleter =
                Thread.new do
                  delete_session(session_id: session_id, protocol_version: protocol_version)
                rescue StandardError
                  nil
                end
              deleter.join([0.2, remaining_s].min)
              deleter.kill if deleter.alive?
            end
          end

          safe_close_client(stream_client)
          safe_close_client(client)
          safe_close_client(sse_stream_client)

          nil
        rescue ArgumentError, TypeError
          nil
        end

        private

        def build_http_clients!
          require_httpx!

          unless ::HTTPX::Request.method_defined?(:stream) && ::HTTPX::Request.method_defined?(:stream=)
            ::HTTPX::Request.class_eval do
              attr_accessor :stream
            end
          end

          timeout_opts = {
            request_timeout: @timeout_s,
            connect_timeout: @open_timeout_s,
            read_timeout: @read_timeout_s,
          }

          base = @http_client || ::HTTPX

          session =
            if base == ::HTTPX
              ::HTTPX.with(timeout: timeout_opts)
            elsif base.is_a?(::HTTPX::Session)
              base.with(timeout: timeout_opts)
            else
              raise ArgumentError, "http_client must be ::HTTPX or an instance of ::HTTPX::Session (got #{base.class})"
            end

          @client = session
          @stream_client = session.plugin(:stream).with(timeout: timeout_opts)

          sse_timeout_opts = timeout_opts.merge(request_timeout: nil, read_timeout: nil)
          sse_base_session =
            if base == ::HTTPX
              ::HTTPX.with(timeout: sse_timeout_opts)
            else
              base.with(timeout: sse_timeout_opts)
            end

          @sse_stream_client = sse_base_session.plugin(:stream).with(timeout: sse_timeout_opts)
        end

        def require_httpx!
          require "httpx"
        rescue LoadError => e
          raise LoadError, "The 'httpx' gem is required to use MCP Streamable HTTP transport. " \
                           "Add `gem 'httpx'` to your Gemfile.", cause: e
        end

        def worker_loop
          loop do
            job = nil

            @mutex.synchronize do
              @cv.wait(@mutex, 0.2) while !@closed && @queue.empty?
              return if @closed

              job = @queue.shift
            end

            next unless job

            process_job(job)
          end
        rescue StandardError => e
          safe_call(@on_stderr_line, "mcp streamable_http worker error: #{e.class}: #{e.message}")
          on_close = nil
          notify = false
          details = { error_class: e.class.name, message: e.message.to_s }

          @mutex.synchronize do
            notify = !@closed
            @closed = true
            @sse_stop = true
            on_close = @on_close
            @queue.clear
            @inflight.clear
            @cv.broadcast
          end

          stop_sse_stream!
          safe_close_client(@sse_stream_client)
          safe_close_client(@stream_client)
          safe_close_client(@client)

          safe_call_close(on_close, details) if notify
        end

        def process_job(job)
          id = job.id
          method_name = job.method.to_s
          token = job.token

          if token && token_cancelled?(token)
            cleanup_inflight(id)
            return
          end

          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          if method_name == "initialize"
            handle_post(job, include_protocol_headers: false, include_session_id: false, extra_headers: job.dynamic_headers)
          else
            handle_post(job, include_protocol_headers: true, include_session_id: true, extra_headers: job.dynamic_headers)
          end

          elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0).round(1)
          safe_call(@on_stderr_line, "mcp http ok method=#{method_name} id=#{id.inspect} ms=#{elapsed_ms}")
        rescue StandardError => e
          if id.nil?
            safe_call(@on_stderr_line, "mcp http error method=#{method_name} ms=? err=#{e.class}: #{e.message}")
          else
            emit_error_response(id, code: "TRANSPORT_ERROR", message: "#{e.class}: #{e.message}")
            safe_call(@on_stderr_line, "mcp http error method=#{method_name} id=#{id.inspect} err=#{e.class}: #{e.message}")
          end
        end

        def handle_post(job, include_protocol_headers:, include_session_id:, extra_headers:)
          id = job.id
          token = job.token

          request_headers =
            build_post_headers(
              include_protocol_headers: include_protocol_headers,
              include_session_id: include_session_id,
              extra_headers: extra_headers,
            )

          json = JSON.generate(job.message)

          if id.nil?
            handle_notification_post(json, headers: request_headers, include_session_id: include_session_id)
            return
          end

          stream_response = stream_session.request(:post, @url, headers: request_headers, body: json, stream: true)

          if stream_response.is_a?(::HTTPX::ErrorResponse)
            raise AgentCore::MCP::TransportError, (stream_response.error&.message || "HTTPX request failed")
          end

          if stream_response.status.to_i == 0
            raise AgentCore::MCP::TransportError, "HTTPX request failed"
          end

          status = stream_response.status.to_i
          response_headers = normalize_http_headers(stream_response)
          content_type = downcase_header_map(response_headers).fetch("content-type", "").to_s

          unless status >= 200 && status < 300
            body = read_full_body_safe(stream_response, token: token)
            if include_session_id && current_session_id && session_not_found_http?(status, body)
              emit_error_response(id, code: "MCP_SESSION_NOT_FOUND", message: "MCP session not found")
              return
            end

            emit_error_response(id, code: "HTTP_ERROR", message: "HTTP status #{status}", data: { "status" => status, "body" => truncate_bytes(body) })
            return
          end

          maybe_store_session_id(response_headers) unless include_protocol_headers

          if content_type.include?("text/event-stream")
            handle_sse_stream(job, response: stream_response)
            return
          end

          body = read_full_body_safe(stream_response, token: token)
          parsed = safe_parse_json(body)
          unless parsed.is_a?(Hash)
            emit_error_response(id, code: "INVALID_RESPONSE", message: "Invalid JSON-RPC response")
            return
          end

          return if accepted_ack?(parsed)

          emit_message(parsed) if json_rpc_like_message?(parsed)
        rescue ::HTTPX::HTTPError => e
          status = e.response.status.to_i
          emit_error_response(id, code: "HTTP_ERROR", message: "HTTP status #{status}", data: { "status" => status })
        ensure
          begin
            stream_response&.close
          rescue StandardError
            nil
          end
        end

        def handle_sse_stream(job, response:)
          id = job.id
          token = job.token

          last_event_id = nil
          retry_ms = nil
          reconnects = 0

          loop do
            return if token && token_cancelled?(token)

            parser =
              AgentCore::MCP::SseParser.new(
                max_buffer_bytes: DEFAULT_SSE_MAX_BUFFER_BYTES,
                max_event_data_bytes: @max_response_bytes,
              )
            done = false

            begin
              begin
                response.each do |chunk|
                  break if token && token_cancelled?(token)

                  parser.feed(chunk) do |event|
                    last_event_id = normalize_event_id(event[:id]) || last_event_id
                    retry_ms = event[:retry_ms] || retry_ms

                    data = event[:data].to_s
                    next if data.empty?

                    msg = safe_parse_json(data)
                    unless msg.is_a?(Hash)
                      raise InvalidSseEventDataError, "Invalid JSON in SSE event data"
                    end

                    emit_message(msg)

                    if response_for_request?(msg, id)
                      done = true
                      break
                    end
                  end

                  break if done
                end
              ensure
                unless token && token_cancelled?(token)
                  parser.finish do |event|
                    last_event_id = normalize_event_id(event[:id]) || last_event_id
                    retry_ms = event[:retry_ms] || retry_ms

                    data = event[:data].to_s
                    next if data.empty?

                    msg = safe_parse_json(data)
                    next unless msg.is_a?(Hash)

                    emit_message(msg)
                    done = true if response_for_request?(msg, id)
                  end
                end
              end
            rescue StopIteration
              nil
            rescue AgentCore::MCP::SseParser::EventDataTooLargeError
              emit_error_response(
                id,
                code: "SSE_EVENT_DATA_TOO_LARGE",
                message: "SSE event data exceeded max_bytes",
                data: { "max_bytes" => @max_response_bytes },
              )
              return
            rescue InvalidSseEventDataError
              emit_error_response(id, code: "INVALID_SSE_EVENT_DATA", message: "Invalid JSON in SSE event data")
              return
            rescue ::HTTPX::HTTPError => e
              status = e.response.status.to_i
              if current_session_id && (status == 404 || status == 400)
                emit_error_response(id, code: "MCP_SESSION_NOT_FOUND", message: "MCP session not found")
                return
              end

              emit_error_response(id, code: "HTTP_ERROR", message: "HTTP status #{status}", data: { "status" => status })
              return
            ensure
              begin
                response&.close
              rescue StandardError
                nil
              end
            end

            return if done
            return if token && token_cancelled?(token)

            reconnects += 1
            if reconnects > @sse_max_reconnects
              emit_error_response(id, code: "SSE_RECONNECTS_EXCEEDED", message: "SSE reconnect limit exceeded", data: { "reconnects" => reconnects })
              return
            end

            wait_before_reconnect(retry_ms, reconnects: reconnects)

            response =
              stream_session.request(
                :get,
                @url,
                headers: build_get_headers(last_event_id: last_event_id),
                stream: true,
              )

            if response.is_a?(::HTTPX::ErrorResponse)
              raise AgentCore::MCP::TransportError, (response.error&.message || "HTTPX request failed")
            end

            status = response.status.to_i
            if current_session_id && (status == 404 || status == 400)
              emit_error_response(id, code: "MCP_SESSION_NOT_FOUND", message: "MCP session not found")
              safe_close_response(response)
              return
            end

            unless status >= 200 && status < 300
              emit_error_response(id, code: "HTTP_ERROR", message: "HTTP status #{status}", data: { "status" => status })
              safe_close_response(response)
              return
            end

            content_type = downcase_header_map(normalize_http_headers(response)).fetch("content-type", "").to_s
            unless content_type.include?("text/event-stream")
              emit_error_response(id, code: "HTTP_ERROR", message: "Expected SSE stream", data: { "content_type" => content_type })
              safe_close_response(response)
              return
            end
          end
        rescue StandardError => e
          emit_error_response(id, code: "TRANSPORT_ERROR", message: "#{e.class}: #{e.message}")
        end

        # --- Header building ---

        def build_post_headers(include_protocol_headers:, include_session_id:, extra_headers:)
          out = base_headers_for_post(extra_headers: extra_headers)

          if include_protocol_headers
            protocol_version = current_protocol_version!
            out[AgentCore::MCP::MCP_PROTOCOL_VERSION_HEADER] = protocol_version
          end

          if include_session_id
            session_id = current_session_id
            out[AgentCore::MCP::MCP_SESSION_ID_HEADER] = session_id if session_id
          end

          out
        end

        def build_get_headers(last_event_id:)
          out = base_headers_for_get(extra_headers: resolve_headers_provider!)

          protocol_version = current_protocol_version!
          out[AgentCore::MCP::MCP_PROTOCOL_VERSION_HEADER] = protocol_version

          session_id = current_session_id
          out[AgentCore::MCP::MCP_SESSION_ID_HEADER] = session_id if session_id
          out[AgentCore::MCP::LAST_EVENT_ID_HEADER] = last_event_id if last_event_id

          out
        end

        def base_headers_for_post(extra_headers:)
          base = {
            "Accept" => AgentCore::MCP::HTTP_ACCEPT_POST,
            "Content-Type" => "application/json",
          }

          extra = normalize_headers(extra_headers)
          merged = base.merge(@headers).merge(extra)
          merged["Accept"] = AgentCore::MCP::HTTP_ACCEPT_POST
          merged["Content-Type"] = "application/json"
          merged
        end

        def base_headers_for_get(extra_headers:)
          base = { "Accept" => AgentCore::MCP::HTTP_ACCEPT_GET }
          extra = normalize_headers(extra_headers)
          merged = base.merge(@headers).merge(extra)
          merged["Accept"] = AgentCore::MCP::HTTP_ACCEPT_GET
          merged
        end

        # --- Helpers ---

        def normalize_headers(value)
          return {} if value.nil?
          raise ArgumentError, "headers must be a Hash" unless value.is_a?(Hash)

          value.each_with_object({}) do |(k, v), out|
            key = k.to_s
            next if key.strip.empty?
            next if v.nil?

            out[key] = v.to_s
          end
        end

        def normalize_headers_provider(value)
          return nil if value.nil?
          return value if value.respond_to?(:call)

          raise ArgumentError, "headers_provider must respond to #call"
        end

        def resolve_headers_provider!
          provider = @headers_provider
          return {} unless provider

          raw = provider.call
          unless raw.is_a?(Hash)
            safe_call(@on_stderr_line, "mcp http headers_provider invalid: expected Hash")
            raise AgentCore::MCP::TransportError, "headers_provider must return a Hash"
          end

          normalize_headers(raw)
        rescue AgentCore::MCP::TransportError
          raise
        rescue StandardError => e
          safe_call(@on_stderr_line, "mcp http headers_provider failed: #{e.class}")
          raise AgentCore::MCP::TransportError, "headers_provider failed"
        end

        def token_cancelled?(token)
          @mutex.synchronize { token.cancelled == true }
        end

        def cleanup_inflight(id)
          @mutex.synchronize { @inflight.delete(id) }
        end

        def current_session_id
          @mutex.synchronize do
            s = @session_id.to_s.strip
            s.empty? ? nil : s
          end
        end

        def current_protocol_version!
          @mutex.synchronize do
            s = @protocol_version.to_s.strip
            raise AgentCore::MCP::TransportError, "protocol_version is required after initialize" if s.empty?

            s
          end
        end

        def stream_session = @stream_client
        def json_session = @client

        def read_full_body_safe(response, token:)
          max_bytes = @max_response_bytes
          full = +"".b

          begin
            response.each do |chunk|
              break if token && token_cancelled?(token)
              str = chunk.to_s
              raise BodyTooLargeError, "HTTP response body exceeded max_bytes" if full.bytesize + str.bytesize > max_bytes

              full << str
            end
          rescue StopIteration
            nil
          rescue BodyTooLargeError
            raise
          rescue StandardError => e
            safe_call(@on_stderr_line, "mcp http body read error: #{e.class}: #{e.message}")
          end

          full.to_s
        end

        def handle_notification_post(json, headers:, include_session_id:)
          response = json_session.post(@url, headers: headers, body: json)

          if response.is_a?(::HTTPX::ErrorResponse)
            raise AgentCore::MCP::TransportError, (response.error&.message || "HTTPX request failed")
          end

          status = response.status.to_i
          if include_session_id && current_session_id && (status == 404 || status == 400)
            safe_call(@on_stderr_line, "mcp http notification got #{status} (session not found)")
          end

          unless status >= 200 && status < 300
            safe_call(@on_stderr_line, "mcp http notification status=#{status}")
          end
        ensure
          safe_close_response(response)
        end

        def normalize_http_headers(response)
          response.headers.to_h.each_with_object({}) do |(k, v), out|
            out[k.to_s] = v.is_a?(Array) ? v.join(", ") : v.to_s
          end
        end

        def downcase_header_map(headers)
          headers.each_with_object({}) do |(k, v), out|
            out[k.to_s.downcase] = v
          end
        end

        def maybe_store_session_id(headers)
          value = downcase_header_map(headers).fetch(AgentCore::MCP::MCP_SESSION_ID_HEADER.downcase, nil).to_s.strip
          value = nil if value.empty?

          should_restart = false

          @mutex.synchronize do
            old = @session_id
            @session_id = value
            should_restart = @started && !@closed && old.to_s != value.to_s
          end

          if should_restart
            stop_sse_stream!
            maybe_start_sse_stream!
          else
            maybe_start_sse_stream!
          end
        end

        def normalize_event_id(value)
          s = value.to_s.strip
          s.empty? ? nil : s
        end

        def response_for_request?(msg, request_id)
          return false unless msg.is_a?(Hash)

          id = msg.fetch("id", nil)
          return false if id.nil?

          matches =
            id == request_id ||
              (id.is_a?(Integer) && request_id.is_a?(String) && request_id.match?(/\A\d+\z/) && id == request_id.to_i) ||
              (id.is_a?(String) && request_id.is_a?(Integer) && id.match?(/\A\d+\z/) && id.to_i == request_id)

          return false unless matches

          msg.key?("result") || msg.key?("error")
        end

        def safe_parse_json(str)
          JSON.parse(str.to_s)
        rescue JSON::ParserError
          nil
        end

        def emit_message(msg)
          cleanup_inflight_for_response(msg)
          safe_call(@on_stdout_line, JSON.generate(msg))
        rescue StandardError
          nil
        end

        def emit_error_response(id, code:, message:, data: nil)
          err = { "code" => code, "message" => message }
          err["data"] = data if data

          emit_message({ "jsonrpc" => "2.0", "id" => id, "error" => err })
        end

        def truncate_bytes(value, max_bytes: 2000)
          s = value.to_s
          return s if s.bytesize <= max_bytes

          s.byteslice(0, max_bytes).to_s
        end

        MINIMUM_RETRY_SECONDS = 1.0
        private_constant :MINIMUM_RETRY_SECONDS

        def wait_before_reconnect(retry_ms, reconnects:)
          ms = retry_ms.is_a?(Integer) ? retry_ms : nil
          seconds =
            if ms
              [ms / 1000.0, MINIMUM_RETRY_SECONDS].max
            else
              case reconnects
              when 1 then 1.0
              when 2 then 2.0
              when 3 then 5.0
              else 10.0
              end
            end

          @sleep_fn.call(seconds) if seconds.positive?
        rescue StandardError
          nil
        end

        def send_cancel_notification(request_id, reason:, session_id:, protocol_version:)
          params = { "requestId" => request_id }
          reason_str = reason.to_s.strip
          params["reason"] = reason_str unless reason_str.empty?

          msg = { "jsonrpc" => "2.0", "method" => "notifications/cancelled", "params" => params }

          headers = base_headers_for_post(extra_headers: resolve_headers_provider!)
          headers[AgentCore::MCP::MCP_PROTOCOL_VERSION_HEADER] = protocol_version.to_s
          headers[AgentCore::MCP::MCP_SESSION_ID_HEADER] = session_id.to_s if session_id && !session_id.to_s.strip.empty?

          response = json_session.post(@url, headers: headers, body: JSON.generate(msg))
          safe_close_response(response)
          true
        rescue StandardError
          false
        end

        def delete_session(session_id:, protocol_version:)
          headers = base_headers_for_get(extra_headers: resolve_headers_provider!)
          headers[AgentCore::MCP::MCP_PROTOCOL_VERSION_HEADER] = protocol_version.to_s
          headers[AgentCore::MCP::MCP_SESSION_ID_HEADER] = session_id.to_s

          response = json_session.delete(@url, headers: headers)
          status = response.status.to_i
          safe_close_response(response)
          return true if status == 405

          status >= 200 && status < 300
        rescue StandardError
          false
        end

        def safe_call(callable, line)
          return unless callable&.respond_to?(:call)

          callable.call(line.to_s)
        rescue StandardError
          nil
        end

        def safe_call_close(callable, details)
          return unless callable&.respond_to?(:call)

          callable.call(details)
        rescue StandardError
          nil
        end

        def safe_close_response(response)
          response&.close
        rescue StandardError
          nil
        end

        def safe_close_client(client)
          client&.close if client&.respond_to?(:close)
        rescue StandardError
          nil
        end

        def should_start_sse_stream_unsafe?
          return false unless @started
          return false if @closed

          session_id = @session_id.to_s.strip
          return false if session_id.empty?

          protocol_version = @protocol_version.to_s.strip
          return false if protocol_version.empty?

          @sse_thread.nil? || !@sse_thread.alive? || @sse_session_id.to_s != session_id
        end

        def maybe_start_sse_stream!
          session_id = nil
          protocol_version = nil
          sse_thread = nil
          sse_session_id = nil

          @mutex.synchronize do
            return nil unless should_start_sse_stream_unsafe?

            session_id = @session_id.to_s.strip
            protocol_version = @protocol_version.to_s.strip

            @sse_stop = false
            @sse_session_id = session_id

            sse_thread = Thread.new { sse_loop(session_id: session_id, protocol_version: protocol_version) }
            @sse_thread = sse_thread
            sse_session_id = @sse_session_id
          end

          safe_call(@on_stderr_line, "mcp sse started session_id=#{sse_session_id}")
          nil
        rescue StandardError => e
          safe_call(@on_stderr_line, "mcp sse start failed: #{e.class}: #{e.message}")
          nil
        end

        def stop_sse_stream!
          sse_thread = nil
          sse_response = nil

          @mutex.synchronize do
            sse_thread = @sse_thread
            @sse_thread = nil

            @sse_stop = true

            sse_response = @sse_response
            @sse_response = nil
            @sse_session_id = nil
          end

          safe_close_response(sse_response)
          sse_thread&.join(0.2)
          if sse_thread&.alive?
            sse_thread.kill
            sse_thread.join(0.1)
          end

          nil
        rescue StandardError
          nil
        end

        def sse_loop(session_id:, protocol_version:)
          reconnects = 0
          last_event_id = nil
          retry_ms = nil

          loop do
            break if sse_should_stop?(session_id: session_id)

            response =
              sse_stream_session.request(
                :get,
                @url,
                headers: build_sse_get_headers(session_id: session_id, protocol_version: protocol_version, last_event_id: last_event_id),
                stream: true,
              )

            if response.is_a?(::HTTPX::ErrorResponse)
              raise AgentCore::MCP::TransportError, (response.error&.message || "HTTPX request failed")
            end

            status = response.status.to_i
            response_headers = normalize_http_headers(response)
            content_type = downcase_header_map(response_headers).fetch("content-type", "").to_s

            if status == 404 || status == 400 || status == 405
              safe_call(@on_stderr_line, "mcp sse connect status=#{status}")
              safe_close_response(response)
              return
            end

            unless status >= 200 && status < 300
              safe_call(@on_stderr_line, "mcp sse connect http_error status=#{status}")
              safe_close_response(response)
              return
            end

            unless content_type.include?("text/event-stream")
              safe_call(@on_stderr_line, "mcp sse connect bad content-type=#{content_type.inspect}")
              safe_close_response(response)
              return
            end

            @mutex.synchronize { @sse_response = response }

            parser =
              AgentCore::MCP::SseParser.new(
                max_buffer_bytes: DEFAULT_SSE_MAX_BUFFER_BYTES,
                max_event_data_bytes: @max_response_bytes,
              )

            begin
              response.each do |chunk|
                break if sse_should_stop?(session_id: session_id)

                parser.feed(chunk) do |event|
                  last_event_id = normalize_event_id(event[:id]) || last_event_id
                  retry_ms = event[:retry_ms] || retry_ms

                  data = event[:data].to_s
                  next if data.empty?

                  msg = safe_parse_json(data)
                  unless msg.is_a?(Hash)
                    safe_call(@on_stderr_line, "mcp sse event invalid json")
                    next
                  end

                  emit_message(msg)
                end
              end
            rescue StopIteration
              nil
            rescue AgentCore::MCP::SseParser::EventDataTooLargeError
              safe_call(@on_stderr_line, "mcp sse event data too large")
              return
            ensure
              @mutex.synchronize { @sse_response = nil }
              safe_close_response(response)
            end

            break if sse_should_stop?(session_id: session_id)

            reconnects += 1
            if reconnects > @sse_max_reconnects
              safe_call(@on_stderr_line, "mcp sse reconnects exceeded reconnects=#{reconnects}")
              return
            end

            wait_before_reconnect(retry_ms, reconnects: reconnects)
          end
        rescue ::HTTPX::HTTPError => e
          status = e.response.status.to_i
          safe_call(@on_stderr_line, "mcp sse http_error status=#{status}")
        rescue StandardError => e
          safe_call(@on_stderr_line, "mcp sse error: #{e.class}: #{e.message}")
        ensure
          @mutex.synchronize do
            @sse_response = nil
            @sse_thread = nil
            @sse_session_id = nil
          end
        end

        def sse_should_stop?(session_id:)
          @mutex.synchronize do
            return true if @closed
            return true if @sse_stop
            return true if @session_id.to_s.strip != session_id.to_s.strip

            false
          end
        rescue StandardError
          true
        end

        def build_sse_get_headers(session_id:, protocol_version:, last_event_id:)
          out = base_headers_for_get(extra_headers: resolve_headers_provider!)
          out[AgentCore::MCP::MCP_PROTOCOL_VERSION_HEADER] = protocol_version.to_s
          out[AgentCore::MCP::MCP_SESSION_ID_HEADER] = session_id.to_s
          out[AgentCore::MCP::LAST_EVENT_ID_HEADER] = last_event_id if last_event_id
          out
        end

        def sse_stream_session = @sse_stream_client

        def cleanup_inflight_for_response(msg)
          return unless msg.is_a?(Hash)

          id = msg.fetch("id", nil)
          return if id.nil?
          return unless msg.key?("result") || msg.key?("error")

          @mutex.synchronize do
            @inflight.delete(id)
            @inflight.delete(id.to_s) if id.is_a?(Integer)
            if id.is_a?(String) && id.match?(/\A\d+\z/)
              @inflight.delete(id.to_i)
            end
          end

          nil
        rescue StandardError
          nil
        end

        def session_not_found_http?(status, body)
          return true if status.to_i == 404
          return false unless status.to_i == 400

          parsed = safe_parse_json(body)
          err = parsed.is_a?(Hash) ? parsed.fetch("error", nil) : nil
          err.to_s.downcase.include?("session")
        end

        def accepted_ack?(parsed)
          parsed.is_a?(Hash) && parsed.fetch("accepted", false) == true
        end

        def json_rpc_like_message?(parsed)
          parsed.is_a?(Hash) && (parsed.key?("jsonrpc") || parsed.key?("id") || parsed.key?("method"))
        end
      end
    end
  end
end
