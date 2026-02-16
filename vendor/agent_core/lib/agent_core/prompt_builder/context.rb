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
                  :agent_config, :tool_policy, :execution_context,
                  :skills_store, :include_skill_locations,
                  :prompt_mode, :prompt_injection_items

      # @param system_prompt [String] The system prompt template
      # @param chat_history [ChatHistory::Base] Conversation history
      # @param tools_registry [Tools::Registry] Available tools
      # @param memory_results [Array<Memory::Entry>] Relevant memory entries
      # @param user_message [String, nil] Current user input
      # @param variables [Hash] Template variables
      # @param agent_config [Hash] Agent configuration (for pipeline customization)
      # @param tool_policy [Tools::Policy::Base, nil] Tool access policy
      # @param execution_context [ExecutionContext, Hash, nil] Execution context (run_id, auth attributes, etc.)
      # @param skills_store [Resources::Skills::Store, nil] Optional skills store
      # @param include_skill_locations [Boolean] Whether to include skill locations in prompt fragments
      # @param prompt_mode [Symbol] :full or :minimal
      # @param prompt_injection_items [Array<Resources::PromptInjections::Item>] Prompt injection items
      def initialize(
        system_prompt: "",
        chat_history: nil,
        tools_registry: nil,
        memory_results: [],
        user_message: nil,
        variables: {},
        agent_config: {},
        tool_policy: nil,
        execution_context: nil,
        skills_store: nil,
        include_skill_locations: false,
        prompt_mode: :full,
        prompt_injection_items: []
      )
        @system_prompt = system_prompt
        @chat_history = chat_history
        @tools_registry = tools_registry
        @memory_results = Array(memory_results)
        @user_message = user_message
        @variables = (variables || {}).freeze
        @agent_config = (agent_config || {}).freeze
        @tool_policy = tool_policy
        @execution_context = ExecutionContext.from(execution_context)
        @skills_store = skills_store
        @include_skill_locations = include_skill_locations == true
        @prompt_mode = (prompt_mode || :full).to_sym
        @prompt_injection_items = Array(prompt_injection_items).freeze
      end
    end
  end
end
