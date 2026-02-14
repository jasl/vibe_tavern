# frozen_string_literal: true

module AgentCore
  module PromptBuilder
    # The result of building a prompt, ready to send to the LLM.
    #
    # Contains all the data the PromptRunner needs to make an API call.
    class BuiltPrompt
      attr_reader :system_prompt, :messages, :tools, :options

      # @param system_prompt [String] System-level instructions
      # @param messages [Array<Message>] Conversation messages
      # @param tools [Array<Hash>] Tool definitions for the LLM
      # @param options [Hash] LLM options (temperature, max_tokens, etc.)
      def initialize(system_prompt:, messages:, tools: [], options: {})
        @system_prompt = system_prompt
        @messages = messages.freeze
        @tools = tools.freeze
        @options = (options || {}).freeze
      end

      # Whether tools are available in this prompt.
      def has_tools?
        tools && !tools.empty?
      end

      # Estimate total token count for this prompt.
      #
      # Includes system prompt, messages, and tool definitions.
      # Useful for pre-flight budget checks outside the Runner.
      #
      # @param token_counter [Resources::TokenCounter::Base] Token counter implementation
      # @return [Hash] { messages: Integer, tools: Integer, total: Integer }
      def estimate_tokens(token_counter:)
        all_messages = if system_prompt && !system_prompt.empty?
          [Message.new(role: :system, content: system_prompt)] + messages.to_a
        else
          messages.to_a
        end

        msg_tokens = token_counter.count_messages(all_messages)
        tool_tokens = has_tools? ? token_counter.count_tools(tools) : 0

        { messages: msg_tokens, tools: tool_tokens, total: msg_tokens + tool_tokens }
      end

      def to_h
        {
          system_prompt: system_prompt,
          messages: messages.map { |m| m.respond_to?(:to_h) ? m.to_h : m },
          tools: tools,
          options: options,
        }
      end
    end
  end
end
