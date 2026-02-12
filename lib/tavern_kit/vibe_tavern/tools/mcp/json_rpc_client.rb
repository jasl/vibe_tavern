# frozen_string_literal: true

require "json"

require_relative "constants"
require_relative "errors"

module TavernKit
  module VibeTavern
    module Tools
      module MCP
        class JsonRpcError < StandardError
          attr_reader :code, :data

          def initialize(code, message, data: nil)
            super(message.to_s)
            @code = code
            @data = data
          end
        end

        class JsonRpcClient
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

          def initialize(transport:, timeout_s: MCP::DEFAULT_TIMEOUT_S, on_notification: nil)
            raise ArgumentError, "transport is required" if transport.nil?

            @transport = transport
            @timeout_s = Float(timeout_s)
            raise ArgumentError, "timeout_s must be positive" if @timeout_s <= 0

            @on_notification = on_notification.respond_to?(:call) ? on_notification : nil

            @pending = {}
            @pending_mutex = Mutex.new
            @next_id = 1
            @started = false
            @closed = false
          end

          def start
            @pending_mutex.synchronize do
              raise MCP::Errors::ClosedError, "client is closed" if @closed
              return self if @started

              if @transport.respond_to?(:on_stdout_line=)
                @transport.on_stdout_line = method(:handle_stdout_line)
              end

              @transport.start
              @started = true
            end

            self
          end

          def request(method, params = {})
            method_name = method.to_s
            raise ArgumentError, "method is required" if method_name.strip.empty?

            pending = PendingRequest.new
            id = nil

            @pending_mutex.synchronize do
              raise MCP::Errors::ClosedError, "client is closed" if @closed
              raise MCP::Errors::TransportError, "client is not started" unless @started

              id = @next_id
              @next_id += 1
              @pending[id] = pending
            end

            msg = { "jsonrpc" => "2.0", "id" => id, "method" => method_name }
            msg["params"] = params if !params.nil?

            begin
              @transport.send_message(msg)
            rescue StandardError => e
              @pending_mutex.synchronize { @pending.delete(id) }
              raise e
            end

            await_pending!(id, pending, method_name)
          end

          def notify(method, params = nil)
            method_name = method.to_s
            raise ArgumentError, "method is required" if method_name.strip.empty?

            @pending_mutex.synchronize do
              raise MCP::Errors::ClosedError, "client is closed" if @closed
              raise MCP::Errors::TransportError, "client is not started" unless @started
            end

            msg = { "jsonrpc" => "2.0", "method" => method_name }
            msg["params"] = params if !params.nil?

            @transport.send_message(msg)
            true
          end

          def close
            pending = nil

            @pending_mutex.synchronize do
              return nil if @closed

              @closed = true
              pending = @pending.dup
              @pending.clear
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

          def await_pending!(id, pending, method_name)
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout_s

            pending.mutex.synchronize do
              until pending.done
                remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
                break if remaining <= 0

                pending.cv.wait(pending.mutex, remaining)
              end
            end

            unless pending.done
              @pending_mutex.synchronize { @pending.delete(id) }
              raise MCP::Errors::TimeoutError, "MCP request timed out: #{method_name}"
            end

            if pending.error
              err = pending.error.is_a?(Hash) ? pending.error : {}
              code = err.fetch("code", nil)
              message = err.fetch("message", nil)
              data = err.fetch("data", nil)
              raise MCP::JsonRpcError.new(code, message, data: data)
            end

            pending.result
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

          def alternate_id_lookup(id)
            case id
            when Integer
              id.to_s
            when String
              return nil unless id.match?(/\A\d+\z/)

              id.to_i
            else
              nil
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
  end
end
