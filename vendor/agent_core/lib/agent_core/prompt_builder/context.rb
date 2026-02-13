# frozen_string_literal: true

module AgentCore
  module PromptBuilder
    # Context bag passed to the pipeline during prompt building.
    #
    # Contains all the data sources the pipeline may draw from.
    # Acts as a read-only data transfer object.
    class Context
      attr_reader :system_prompt, :chat_history, :tools_registry,
                  :memory_results, :user_message, :variables,
                  :agent_config, :tool_policy

      # @param system_prompt [String] The system prompt template
      # @param chat_history [ChatHistory::Base] Conversation history
      # @param tools_registry [Tools::Registry] Available tools
      # @param memory_results [Array<Memory::Entry>] Relevant memory entries
      # @param user_message [String, nil] Current user input
      # @param variables [Hash] Template variables
      # @param agent_config [Hash] Agent configuration (for pipeline customization)
      # @param tool_policy [Tools::Policy::Base, nil] Tool access policy
      def initialize(
        system_prompt: "",
        chat_history: nil,
        tools_registry: nil,
        memory_results: [],
        user_message: nil,
        variables: {},
        agent_config: {},
        tool_policy: nil
      )
        @system_prompt = system_prompt
        @chat_history = chat_history
        @tools_registry = tools_registry
        @memory_results = Array(memory_results)
        @user_message = user_message
        @variables = (variables || {}).freeze
        @agent_config = (agent_config || {}).freeze
        @tool_policy = tool_policy
      end
    end
  end
end
