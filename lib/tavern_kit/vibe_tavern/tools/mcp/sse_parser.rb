# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module Tools
      module MCP
        class SseParser
          class EventDataTooLargeError < ArgumentError; end

          def initialize(max_buffer_bytes: 1_000_000, max_event_data_bytes: nil)
            @max_buffer_bytes = Integer(max_buffer_bytes)
            raise ArgumentError, "max_buffer_bytes must be positive" if @max_buffer_bytes <= 0

            @max_event_data_bytes = max_event_data_bytes.nil? ? nil : Integer(max_event_data_bytes)
            if !@max_event_data_bytes.nil? && @max_event_data_bytes <= 0
              raise ArgumentError, "max_event_data_bytes must be positive"
            end

            @buffer = +"".b
            reset_event!
          end

          def feed(chunk)
            chunk = chunk.to_s.b
            return if chunk.empty?

            @buffer << chunk
            raise ArgumentError, "SSE buffer exceeded max_buffer_bytes" if @buffer.bytesize > @max_buffer_bytes

            each_line do |line|
              process_line(line) { |event| yield event if block_given? }
            end

            nil
          end

          def finish
            if !@buffer.empty?
              # Process the final line even if it wasn't newline-terminated.
              process_line(@buffer.to_s.delete_suffix("\r")) { |event| yield event if block_given? }
              @buffer.clear
            end

            flush_event { |event| yield event if block_given? }
            nil
          end

          private

          def each_line
            while (idx = @buffer.index("\n"))
              raw = @buffer.byteslice(0, idx)
              @buffer = @buffer.byteslice(idx + 1, @buffer.bytesize - idx - 1) || +"".b

              line = raw.to_s.delete_suffix("\r")
              yield line
            end
          end

          def process_line(line)
            if line.empty?
              flush_event { |event| yield event if block_given? }
              return
            end

            return if line.start_with?(":")

            field, rest = line.split(":", 2)
            value = rest.nil? ? "" : rest.sub(/\A /, "")

            case field
            when "id"
              @event_id = value
            when "event"
              @event_name = value
            when "data"
              enforce_event_data_limit!(value)
              @data_lines << value
            when "retry"
              ms = Integer(value, exception: false)
              @retry_ms = ms if ms && ms >= 0
            end
          end

          def flush_event
            has_any =
              !@event_id.nil? ||
                !@event_name.nil? ||
                !@retry_ms.nil? ||
                !@data_lines.empty?

            if has_any
              data = @data_lines.empty? ? "" : @data_lines.join("\n")
              yield({ id: @event_id, event: @event_name, data: data, retry_ms: @retry_ms }) if block_given?
            end

            reset_event!
          end

          def reset_event!
            @event_id = nil
            @event_name = nil
            @retry_ms = nil
            @data_lines = []
            @event_data_bytes = 0
          end

          def enforce_event_data_limit!(line)
            max = @max_event_data_bytes
            return unless max

            added_bytes = line.to_s.bytesize
            added_bytes += 1 unless @data_lines.empty?

            if @event_data_bytes + added_bytes > max
              raise EventDataTooLargeError, "SSE event data exceeded max_event_data_bytes"
            end

            @event_data_bytes += added_bytes
          end
        end
      end
    end
  end
end
