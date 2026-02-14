# frozen_string_literal: true

module AgentCore
  module MCP
    module Transport
      # Abstract base class for MCP transports.
      #
      # Transports handle the low-level communication between the MCP client
      # and server. They are responsible for sending/receiving JSON messages
      # and managing the connection lifecycle.
      #
      # Subclasses must implement: start, send_message, close.
      #
      # @example
      #   transport = SomeTransport.new(...)
      #   transport.on_stdout_line = ->(line) { handle_message(line) }
      #   transport.on_stderr_line = ->(line) { log_debug(line) }
      #   transport.on_close = ->(details) { handle_disconnect(details) }
      #   transport.start
      class Base
        attr_accessor :on_stdout_line, :on_stderr_line, :on_close

        # Start the transport connection.
        # @return [self]
        def start
          raise AgentCore::NotImplementedError, "#{self.class}#start must be implemented"
        end

        # Send a JSON-RPC message.
        # @param _hash [Hash] The message to send
        # @return [true]
        def send_message(_hash)
          raise AgentCore::NotImplementedError, "#{self.class}#send_message must be implemented"
        end

        # Close the transport connection.
        # @param timeout_s [Float] Maximum time to wait for graceful shutdown
        # @return [nil]
        def close(timeout_s: 2.0) # rubocop:disable Lint/UnusedMethodArgument
          raise AgentCore::NotImplementedError, "#{self.class}#close must be implemented"
        end
      end
    end
  end
end
