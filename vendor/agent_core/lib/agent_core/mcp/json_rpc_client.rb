# frozen_string_literal: true

require "json"

module AgentCore
  module MCP
    # JSON-RPC 2.0 client over an MCP transport.
    #
    # Sends JSON-RPC requests and notifications, correlates responses
    # to pending requests using Mutex + ConditionVariable, and handles
    # timeouts with CLOCK_MONOTONIC deadlines.
    #
    # Thread-safe: all pending-request state is guarded by @pending_mutex.
    class JsonRpcClient
      # Internal tracking object for an in-flight request.
      class PendingRequest
        attr_reader :mutex, :cv
        attr_accessor :done, :result, :error

        def initialize
          @mutex = Mutex.new
          @cv = ConditionVariable.new
          @done = false
          @result = nil
          @error = nil
        end
      end

      # @param transport [Transport::Base] The underlying transport
      # @param timeout_s [Float] Default request timeout
      # @param on_notification [#call, nil] Callback for server notifications
      def initialize(transport:, timeout_s: AgentCore::MCP::DEFAULT_TIMEOUT_S, on_notification: nil)
        raise ArgumentError, "transport is required" if transport.nil?

        @transport = transport
        @timeout_s = Float(timeout_s)
        raise ArgumentError, "timeout_s must be positive" if @timeout_s <= 0

        @on_notification = on_notification.respond_to?(:call) ? on_notification : nil

        @pending = {}
        @pending_mutex = Mutex.new
        @next_id = 1
        @started = false
        @starting = false
        @start_cv = ConditionVariable.new
        @closed = false
      end

      # Start the client (wires callbacks and starts transport).
      # @return [self]
      def start
        @pending_mutex.synchronize do
          raise AgentCore::MCP::ClosedError, "client is closed" if @closed
          return self if @started

          while @starting
            @start_cv.wait(@pending_mutex)
            raise AgentCore::MCP::ClosedError, "client is closed" if @closed
            return self if @started
          end

          @starting = true
        end

        begin
          wire_transport_callbacks!
          @transport.start
        rescue StandardError
          @pending_mutex.synchronize do
            @starting = false
            @start_cv.broadcast
          end
          raise
        end

        should_close_transport = false

        @pending_mutex.synchronize do
          if @closed
            should_close_transport = true
          else
            @started = true
          end

          @starting = false
          @start_cv.broadcast
        end

        if should_close_transport
          begin
            @transport.close if @transport.respond_to?(:close)
          rescue StandardError
            nil
          end

          raise AgentCore::MCP::ClosedError, "client is closed"
        end

        self
      end

      # Send a JSON-RPC request and wait for the response.
      #
      # @param method [String] The RPC method name
      # @param params [Hash] The RPC params
      # @param timeout_s [Float, nil] Override timeout for this request
      # @return [Object] The result field from the JSON-RPC response
      # @raise [AgentCore::MCP::TimeoutError] If the request times out
      # @raise [AgentCore::MCP::JsonRpcError] If the server returns an error
      def request(method, params = {}, timeout_s: nil)
        method_name = method.to_s
        raise ArgumentError, "method is required" if method_name.strip.empty?

        pending = PendingRequest.new
        id = nil

        @pending_mutex.synchronize do
          raise AgentCore::MCP::ClosedError, "client is closed" if @closed
          raise AgentCore::MCP::TransportError, "client is not started" unless @started

          id = @next_id
          @next_id += 1
          @pending[id] = pending
        end

        msg = { "jsonrpc" => "2.0", "id" => id, "method" => method_name }
        msg["params"] = params unless params.nil?

        begin
          @transport.send_message(msg)
        rescue StandardError => e
          @pending_mutex.synchronize { @pending.delete(id) }
          raise e
        end

        await_pending!(id, pending, method_name, timeout_s: timeout_s)
      end

      # Send a JSON-RPC notification (no response expected).
      #
      # @param method [String] The RPC method name
      # @param params [Hash, nil] The RPC params
      # @return [true]
      def notify(method, params = nil)
        method_name = method.to_s
        raise ArgumentError, "method is required" if method_name.strip.empty?

        @pending_mutex.synchronize do
          raise AgentCore::MCP::ClosedError, "client is closed" if @closed
          raise AgentCore::MCP::TransportError, "client is not started" unless @started
        end

        msg = { "jsonrpc" => "2.0", "method" => method_name }
        msg["params"] = params unless params.nil?

        @transport.send_message(msg)
        true
      end

      # Close the client and cancel all pending requests.
      # @return [nil]
      def close
        pending = nil

        @pending_mutex.synchronize do
          if @closed
            pending = nil
          else
            @closed = true
            pending = @pending.dup
            @pending.clear
            @start_cv.broadcast if @starting
          end
        end

        pending&.each_value do |p|
          p.mutex.synchronize do
            p.done = true
            p.error = { "code" => "CLOSED", "message" => "client closed", "data" => nil }
            p.cv.broadcast
          end
        end

        @transport.close if @transport.respond_to?(:close)

        nil
      end

      private

      def await_pending!(id, pending, method_name, timeout_s:)
        timeout_s = timeout_s.nil? ? @timeout_s : Float(timeout_s)
        raise ArgumentError, "timeout_s must be positive" if timeout_s <= 0

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_s

        pending.mutex.synchronize do
          until pending.done
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            break if remaining <= 0

            pending.cv.wait(pending.mutex, remaining)
          end
        end

        unless pending.done
          @pending_mutex.synchronize { @pending.delete(id) }
          begin
            if method_name != "initialize"
              if @transport.respond_to?(:cancel_request)
                @transport.cancel_request(id, reason: "timeout")
              else
                @transport.send_message(
                  {
                    "jsonrpc" => "2.0",
                    "method" => "notifications/cancelled",
                    "params" => { "requestId" => id, "reason" => "timeout" },
                  },
                )
              end
            end
          rescue StandardError
            nil
          end
          raise AgentCore::MCP::TimeoutError, "MCP request timed out: #{method_name}"
        end

        if pending.error
          err = pending.error.is_a?(Hash) ? pending.error : {}
          code = err.fetch("code", nil)
          message = err.fetch("message", nil)
          data = err.fetch("data", nil)

          case code.to_s
          when "CLOSED"
            raise AgentCore::MCP::ClosedError, message.to_s
          when "TRANSPORT_CLOSED"
            raise AgentCore::MCP::TransportError, message.to_s
          end

          raise AgentCore::MCP::JsonRpcError.new(code, message, data: data)
        end

        pending.result
      end

      def handle_transport_close(_details = nil)
        pending = nil

        @pending_mutex.synchronize do
          return nil if @closed

          @closed = true
          pending = @pending.dup
          @pending.clear
          @start_cv.broadcast if @starting
        end

        pending&.each_value do |p|
          p.mutex.synchronize do
            p.done = true
            p.error = { "code" => "TRANSPORT_CLOSED", "message" => "transport closed", "data" => _details }
            p.cv.broadcast
          end
        end

        nil
      rescue StandardError
        nil
      end

      def wire_transport_callbacks!
        if @transport.respond_to?(:on_stdout_line=)
          existing_stdout = @transport.respond_to?(:on_stdout_line) ? @transport.on_stdout_line : nil
          handler = method(:handle_stdout_line)

          if existing_stdout&.respond_to?(:call)
            @transport.on_stdout_line =
              lambda do |line|
                handler.call(line)
                begin
                  existing_stdout.call(line)
                rescue StandardError
                  nil
                end
              end
          else
            @transport.on_stdout_line = handler
          end
        end

        if @transport.respond_to?(:on_close=)
          @transport.on_close = method(:handle_transport_close)
        end

        nil
      end

      def handle_stdout_line(line)
        str = line.to_s.strip
        return if str.empty?

        msg = JSON.parse(str)
        return unless msg.is_a?(Hash)

        if msg.key?("id")
          handle_response(msg)
        elsif msg.key?("method")
          handle_notification(msg)
        end
      rescue JSON::ParserError
        nil
      rescue StandardError
        nil
      end

      def handle_response(msg)
        id = msg.fetch("id", nil)
        return if id.nil?

        pending = @pending_mutex.synchronize { @pending.delete(id) }
        if pending.nil?
          alt_id = alternate_id_lookup(id)
          pending = @pending_mutex.synchronize { @pending.delete(alt_id) } if alt_id
        end
        return unless pending

        pending.mutex.synchronize do
          if msg.key?("error")
            pending.error = msg.fetch("error")
          else
            pending.result = msg.fetch("result", nil)
          end

          pending.done = true
          pending.cv.broadcast
        end
      end

      # Handle integer/string ID mismatch between request and response.
      def alternate_id_lookup(id)
        case id
        when Integer
          id.to_s
        when String
          return nil unless id.match?(/\A\d+\z/)

          id.to_i
        end
      end

      def handle_notification(msg)
        method_name = msg.fetch("method", "").to_s
        return unless method_name.start_with?("notifications/")

        callback = @on_notification
        return unless callback

        callback.call(msg)
      rescue StandardError
        nil
      end
    end
  end
end
