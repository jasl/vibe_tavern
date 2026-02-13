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

      def to_h
        {
          system_prompt: system_prompt,
          messages: messages.map { |m| m.respond_to?(:to_h) ? m.to_h : m },
          tools: tools,
          options: options
        }
      end
    end
  end
end
