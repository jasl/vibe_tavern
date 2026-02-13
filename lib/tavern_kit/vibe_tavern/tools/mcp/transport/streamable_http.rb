# frozen_string_literal: true

require "json"

require_relative "base"
require_relative "../constants"
require_relative "../errors"
require_relative "../sse_parser"

module TavernKit
  module VibeTavern
    module Tools
      module MCP
        module Transport
          class StreamableHttp < Base
            DEFAULT_SSE_MAX_RECONNECTS = 20
            DEFAULT_SSE_MAX_BUFFER_BYTES = 1_000_000
            DEFAULT_MAX_RESPONSE_BYTES = 8 * 1024 * 1024

            Token = Struct.new(:cancelled, :reason, keyword_init: true)
            Job = Data.define(:message, :id, :method, :token)

            class BodyTooLargeError < StandardError; end
            class InvalidSseEventDataError < StandardError; end

            attr_reader :session_id

            def initialize(
              url:,
              headers: nil,
              timeout_s: MCP::DEFAULT_TIMEOUT_S,
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
            end

            def protocol_version=(value)
              s = value.to_s.strip
              s = nil if s.empty?

              @mutex.synchronize { @protocol_version = s }
            end

            def start
              @mutex.synchronize do
                raise MCP::Errors::ClosedError, "transport is closed" if @closed
                return self if @started

                build_http_clients!

                @worker = Thread.new { worker_loop }
                @started = true
              end

              self
            end

            def send_message(hash)
              message = hash.is_a?(Hash) ? hash : {}
              id = message.fetch("id", message.fetch(:id, nil))
              method_name = message.fetch("method", message.fetch(:method, "")).to_s

              job = nil

              @mutex.synchronize do
                raise MCP::Errors::ClosedError, "transport is closed" if @closed
                raise MCP::Errors::TransportError, "transport is not started" unless @started

                token = nil
                if !id.nil?
                  raise MCP::Errors::TransportError, "duplicate request id: #{id}" if @inflight.key?(id)

                  token = Token.new(cancelled: false, reason: nil)
                  @inflight[id] = token
                end

                job = Job.new(message: message, id: id, method: method_name, token: token)
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
                token.reason = reason.to_s if !reason.nil?

                @queue.delete_if { |job| job.id == request_id }
                @inflight.delete(request_id)

                session_id = @session_id
                protocol_version = @protocol_version
              end

              # Best-effort cancellation notification; do not block caller.
              if protocol_version && !protocol_version.to_s.strip.empty?
                Thread.new do
                  begin
                    send_cancel_notification(request_id, reason: reason, session_id: session_id, protocol_version: protocol_version)
                  rescue StandardError
                    nil
                  end
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
              protocol_version = nil
              session_id = nil
              client = nil
              stream_client = nil

              @mutex.synchronize do
                return nil if @closed

                @closed = true

                worker = @worker
                @worker = nil

                @queue.clear
                @inflight.clear

                protocol_version = @protocol_version
                session_id = @session_id

                client = @client
                stream_client = @stream_client

                @cv.broadcast
              end

              deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_s
              grace_s = [0.2, timeout_s].min

              worker&.join(grace_s)

              if worker&.alive?
                begin
                  stream_client&.close
                rescue StandardError
                  nil
                end

                begin
                  client&.close if client&.respond_to?(:close)
                rescue StandardError
                  nil
                end

                remaining_s = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
                worker.join(remaining_s) if remaining_s.positive?

                if worker.alive?
                  worker.kill
                  worker.join(0.1)
                end
              elsif session_id && protocol_version && !protocol_version.to_s.strip.empty?
                remaining_s = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
                if remaining_s.positive?
                  begin
                    deleter =
                      Thread.new do
                        delete_session(session_id: session_id, protocol_version: protocol_version)
                      end
                    deleter.join([0.2, remaining_s].min)
                    deleter.kill if deleter.alive?
                  rescue StandardError
                    nil
                  end
                end
              end

              begin
                stream_client&.close
              rescue StandardError
                nil
              end

              begin
                client&.close if client&.respond_to?(:close)
              rescue StandardError
                nil
              end

              nil
            rescue ArgumentError, TypeError
              nil
            end

            private

            def build_http_clients!
              require_httpx!

              # HTTPX stream plugin expects all request objects to respond to `#stream`.
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
            end

            def require_httpx!
              require "httpx"
            rescue LoadError => e
              raise LoadError, "The 'httpx' gem is required to use MCP Streamable HTTP transport", cause: e
            end

            def worker_loop
              loop do
                job = nil

                @mutex.synchronize do
                  while !@closed && @queue.empty?
                    @cv.wait(@mutex, 0.2)
                  end

                  return if @closed

                  job = @queue.shift
                end

                next unless job

                process_job(job)
              end
            rescue StandardError => e
              safe_call(@on_stderr_line, "mcp streamable_http worker error: #{e.class}: #{e.message}")
              on_close = nil
              client = nil
              stream_client = nil
              notify = false

              details = { error_class: e.class.name, message: e.message.to_s }

              @mutex.synchronize do
                notify = !@closed
                @closed = true

                on_close = @on_close
                client = @client
                stream_client = @stream_client

                @queue.clear
                @inflight.clear

                @cv.broadcast
              end

              begin
                stream_client&.close
              rescue StandardError
                nil
              end

              begin
                client&.close if client&.respond_to?(:close)
              rescue StandardError
                nil
              end

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
                handle_post(job, include_protocol_headers: false, include_session_id: false)
              else
                handle_post(job, include_protocol_headers: true, include_session_id: true)
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
            ensure
              cleanup_inflight(id) if id
            end

            def handle_post(job, include_protocol_headers:, include_session_id:)
              id = job.id
              token = job.token

              request_headers =
                build_post_headers(include_protocol_headers: include_protocol_headers, include_session_id: include_session_id)

              json = JSON.generate(job.message)

              if id.nil?
                handle_notification_post(json, headers: request_headers, include_session_id: include_session_id)
                return
              end

              status = nil
              response_headers = {}
              content_type = nil

              body = +"".b

              stream_response = stream_session.request(:post, @url, headers: request_headers, body: json, stream: true)

              if stream_response.is_a?(::HTTPX::ErrorResponse)
                raise MCP::Errors::TransportError, (stream_response.error&.message || "HTTPX request failed")
              end

              if stream_response.status.to_i == 0
                raise MCP::Errors::TransportError, "HTTPX request failed"
              end

              status = stream_response.status.to_i
              response_headers = normalize_http_headers(stream_response)
              content_type = downcase_header_map(response_headers).fetch("content-type", "").to_s

              if status == 404 && include_session_id && current_session_id
                emit_error_response(id, code: "MCP_SESSION_NOT_FOUND", message: "MCP session not found")
                return
              end

              unless status >= 200 && status < 300
                begin
                  body = read_full_body(stream_response, token: token, max_bytes: @max_response_bytes)
                rescue BodyTooLargeError
                  emit_error_response(
                    id,
                    code: "HTTP_BODY_TOO_LARGE",
                    message: "HTTP response body exceeded max_bytes",
                    data: { "max_bytes" => @max_response_bytes, "status" => status, "content_type" => content_type },
                  )
                  return
                end
                emit_error_response(id, code: "HTTP_ERROR", message: "HTTP status #{status}", data: { "status" => status, "body" => truncate_bytes(body) })
                return
              end

              if include_protocol_headers == false
                maybe_store_session_id(response_headers)
              end

              if content_type.include?("text/event-stream")
                handle_sse_stream(job, response: stream_response)
                return
              end

              begin
                body = read_full_body(stream_response, token: token, max_bytes: @max_response_bytes)
              rescue BodyTooLargeError
                emit_error_response(
                  id,
                  code: "HTTP_BODY_TOO_LARGE",
                  message: "HTTP response body exceeded max_bytes",
                  data: { "max_bytes" => @max_response_bytes, "status" => status, "content_type" => content_type },
                )
                return
              end

              parsed = safe_parse_json(body)
              unless parsed.is_a?(Hash)
                emit_error_response(id, code: "INVALID_RESPONSE", message: "Invalid JSON-RPC response")
                return
              end

              emit_message(parsed)
            rescue ::HTTPX::HTTPError => e
              status = e.response.status.to_i
              response_headers = normalize_http_headers(e.response)
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
                  MCP::SseParser.new(
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
                      # Flush the final event on EOF even if it wasn't newline-terminated.
                      # Treat invalid JSON here as a partial/truncated tail and ignore it.
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
                rescue MCP::SseParser::EventDataTooLargeError
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
                  if status == 404 && current_session_id
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
                  raise MCP::Errors::TransportError, (response.error&.message || "HTTPX request failed")
                end

                if response.status.to_i == 0
                  raise MCP::Errors::TransportError, "HTTPX request failed"
                end

                status = response.status.to_i
                if status == 404 && current_session_id
                  emit_error_response(id, code: "MCP_SESSION_NOT_FOUND", message: "MCP session not found")
                  begin
                    response&.close
                  rescue StandardError
                    nil
                  end
                  return
                end

                unless status >= 200 && status < 300
                  emit_error_response(id, code: "HTTP_ERROR", message: "HTTP status #{status}", data: { "status" => status })
                  begin
                    response&.close
                  rescue StandardError
                    nil
                  end
                  return
                end

                content_type = downcase_header_map(normalize_http_headers(response)).fetch("content-type", "").to_s
                unless content_type.include?("text/event-stream")
                  emit_error_response(id, code: "HTTP_ERROR", message: "Expected SSE stream", data: { "content_type" => content_type })
                  begin
                    response&.close
                  rescue StandardError
                    nil
                  end
                  return
                end
              end
            rescue StandardError => e
              emit_error_response(id, code: "TRANSPORT_ERROR", message: "#{e.class}: #{e.message}")
            end

            def build_post_headers(include_protocol_headers:, include_session_id:)
              out = base_headers_for_post

              if include_protocol_headers
                protocol_version = current_protocol_version!
                out[MCP::MCP_PROTOCOL_VERSION_HEADER] = protocol_version
              end

              if include_session_id
                session_id = current_session_id
                out[MCP::MCP_SESSION_ID_HEADER] = session_id if session_id
              end

              out
            end

            def build_get_headers(last_event_id:)
              out = base_headers_for_get

              protocol_version = current_protocol_version!
              out[MCP::MCP_PROTOCOL_VERSION_HEADER] = protocol_version

              session_id = current_session_id
              out[MCP::MCP_SESSION_ID_HEADER] = session_id if session_id

              out[MCP::LAST_EVENT_ID_HEADER] = last_event_id if last_event_id

              out
            end

            def base_headers_for_post
              base = {
                "Accept" => MCP::HTTP_ACCEPT_POST,
                "Content-Type" => "application/json",
              }

              merged = base.merge(@headers)
              merged["Accept"] = MCP::HTTP_ACCEPT_POST
              merged["Content-Type"] = "application/json"
              merged
            end

            def base_headers_for_get
              base = { "Accept" => MCP::HTTP_ACCEPT_GET }
              merged = base.merge(@headers)
              merged["Accept"] = MCP::HTTP_ACCEPT_GET
              merged
            end

            def normalize_headers(value)
              return {} if value.nil?

              unless value.is_a?(Hash)
                raise ArgumentError, "headers must be a Hash"
              end

              value.each_with_object({}) do |(k, v), out|
                key = k.to_s
                next if key.strip.empty?
                next if v.nil?

                out[key] = v.to_s
              end
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
                raise MCP::Errors::TransportError, "protocol_version is required after initialize" if s.empty?

                s
              end
            end

            def stream_session
              @stream_client
            end

            def json_session
              @client
            end

            def read_full_body(response, token:, max_bytes:)
              max_bytes = Integer(max_bytes)
              raise ArgumentError, "max_bytes must be positive" if max_bytes <= 0

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
              rescue ::HTTPX::HTTPError => e
                # Let caller handle status if needed; still keep whatever we have.
                safe_call(@on_stderr_line, "mcp http body read error: #{e.class}: #{e.message}")
              end

              full.to_s
            end

            def handle_notification_post(json, headers:, include_session_id:)
              response = json_session.post(@url, headers: headers, body: json)

              if response.is_a?(::HTTPX::ErrorResponse)
                raise MCP::Errors::TransportError, (response.error&.message || "HTTPX request failed")
              end

              if response.status.to_i == 0
                raise MCP::Errors::TransportError, "HTTPX request failed"
              end

              status = response.status.to_i
              if status == 404 && include_session_id && current_session_id
                safe_call(@on_stderr_line, "mcp http notification got 404 (session not found)")
              end

              unless status >= 200 && status < 300
                safe_call(@on_stderr_line, "mcp http notification status=#{status}")
              end
            ensure
              begin
                response&.close
              rescue StandardError
                nil
              end
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
              value = downcase_header_map(headers).fetch(MCP::MCP_SESSION_ID_HEADER.downcase, nil).to_s.strip
              value = nil if value.empty?

              @mutex.synchronize { @session_id = value }
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

            def wait_before_reconnect(retry_ms, reconnects:)
              ms = retry_ms.is_a?(Integer) ? retry_ms : nil
              seconds =
                if ms
                  ms / 1000.0
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
              reason = reason.to_s.strip
              params["reason"] = reason unless reason.empty?

              msg = { "jsonrpc" => "2.0", "method" => "notifications/cancelled", "params" => params }

              headers = base_headers_for_post
              headers[MCP::MCP_PROTOCOL_VERSION_HEADER] = protocol_version.to_s
              headers[MCP::MCP_SESSION_ID_HEADER] = session_id.to_s if session_id && !session_id.to_s.strip.empty?

              response = json_session.post(@url, headers: headers, body: JSON.generate(msg))
              response&.close
              true
            rescue StandardError
              false
            end

            def delete_session(session_id:, protocol_version:)
              headers = base_headers_for_get
              headers[MCP::MCP_PROTOCOL_VERSION_HEADER] = protocol_version.to_s
              headers[MCP::MCP_SESSION_ID_HEADER] = session_id.to_s

              response = json_session.delete(@url, headers: headers)
              status = response.status.to_i
              response&.close
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
          end
        end
      end
    end
  end
end
