# frozen_string_literal: true

module TavernKit
  module ChatHistory
    # Minimal chat history contract used by prompt-building.
    #
    # - Enumerable yielding messages in chronological order (oldest -> newest)
    # - Messages should be Prompt::Message (recommended), or duck-type as
    #   { role:, content: } (hash keys may be String or Symbol).
    class Base
      include Enumerable

      def append(message) = raise NotImplementedError
      def each(&block) = raise NotImplementedError
      def size = raise NotImplementedError
      def clear = raise NotImplementedError

      # Optional performance override. Default falls back to Enumerable#to_a.
      def last(n)
        to_a.last(n)
      end
    end

    # Wraps an existing Enumerable into a ChatHistory::Base.
    #
    # This is a convenience adapter; app code should prefer implementing a
    # dedicated adapter for streaming/ActiveRecord sources when performance
    # matters.
    class EnumerableAdapter < Base
      def initialize(enum)
        @enum = enum
      end

      def append(message)
        raise NotImplementedError, "underlying history is not appendable" unless @enum.respond_to?(:<<)

        @enum << ChatHistory.coerce_message(message)
      end

      def each(&block)
        return enum_for(:each) unless block

        @enum.each { |msg| block.call(ChatHistory.coerce_message(msg)) }
      end

      def size
        return @enum.size if @enum.respond_to?(:size)

        # Avoid surprising behavior: this materializes. Prefer a real adapter.
        @enum.to_a.size
      end

      def clear
        raise NotImplementedError, "underlying history is not clearable" unless @enum.respond_to?(:clear)

        @enum.clear
      end

      def last(n)
        if @enum.respond_to?(:last)
          Array(@enum.last(n)).map { |msg| ChatHistory.coerce_message(msg) }
        else
          super
        end
      end
    end

    class << self
      # Normalize nil/array/enumerable inputs into a ChatHistory adapter.
      def wrap(input)
        case input
        when nil
          InMemory.new([])
        when Base
          input
        when Array
          InMemory.new(input)
        else
          if input.respond_to?(:each)
            EnumerableAdapter.new(input)
          else
            raise ArgumentError, "Unsupported chat history: #{input.class}. Expected nil, Array, Enumerable, or ChatHistory::Base."
          end
        end
      end

      def coerce_message(value)
        return value if value.is_a?(TavernKit::Prompt::Message)

        if value.is_a?(Hash)
          h = TavernKit::Utils::HashAccessor.wrap(value)
          role = h[:role]
          content = h[:content]
          name = h[:name]
          send_date = h[:send_date]
          attachments = h[:attachments]
          metadata = h[:metadata]

          raise ArgumentError, "message.role is required" if role.nil?
          raise ArgumentError, "message.content is required" if content.nil?

          return TavernKit::Prompt::Message.new(
            role: role.to_s.downcase.to_sym,
            content: content.to_s,
            name: name&.to_s,
            send_date: send_date,
            attachments: attachments,
            metadata: metadata,
          )
        end

        if value.respond_to?(:role) && value.respond_to?(:content)
          return TavernKit::Prompt::Message.new(
            role: value.role.to_s.downcase.to_sym,
            content: value.content.to_s,
            name: value.respond_to?(:name) ? value.name&.to_s : nil,
            send_date: value.respond_to?(:send_date) ? value.send_date : nil,
            attachments: value.respond_to?(:attachments) ? value.attachments : nil,
            metadata: value.respond_to?(:metadata) ? value.metadata : nil,
          )
        end

        raise ArgumentError, "Unsupported message: #{value.class}. Expected Prompt::Message, Hash, or duck-typed message."
      end
    end
  end
end
