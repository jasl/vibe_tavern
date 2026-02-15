# frozen_string_literal: true

require_relative "agent/builder"

module AgentCore
  # Top-level Agent object.
  #
  # Orchestrates: Resources → PromptBuilder → PromptRunner.
  # Constructed via Builder pattern. Serializable (config can be saved/shared).
  #
  # @example Building and using an agent
  #   agent = AgentCore::Agent.build do |b|
  #     b.name = "Assistant"
  #     b.system_prompt = "You are a helpful assistant."
  #     b.model = "claude-sonnet-4-5-20250929"
  #     b.provider = MyProvider.new
  #     b.chat_history = AgentCore::Resources::ChatHistory::InMemory.new
  #     b.tools_registry = registry
  #   end
  #
  #   result = agent.chat("Hello!")
  #   puts result.text
  #
  # @example Streaming
  #   agent.chat_stream("What's the weather?") do |event|
  #     case event
  #     when AgentCore::StreamEvent::TextDelta
  #       print event.text
  #     end
  #   end
  class Agent
    attr_reader :name, :description, :system_prompt, :model,
                :provider, :chat_history, :memory, :tools_registry,
                :tool_policy, :skills_store, :include_skill_locations,
                :prompt_pipeline, :max_turns,
                :token_counter, :context_window, :reserved_output_tokens

    # Build an agent using the Builder DSL.
    # @yield [Builder]
    # @return [Agent]
    def self.build
      builder = Builder.new
      yield builder
      builder.build
    end

    # Create an agent from a serialized config + runtime dependencies.
    #
    # @param config [Hash] Serialized agent config
    # @param provider [Resources::Provider::Base] LLM provider
    # @param chat_history [Resources::ChatHistory::Base, nil]
    # @param memory [Resources::Memory::Base, nil]
    # @param tools_registry [Resources::Tools::Registry, nil]
    # @param tool_policy [Resources::Tools::Policy::Base, nil]
    # @param prompt_pipeline [PromptBuilder::Pipeline, nil]
    # @return [Agent]
    def self.from_config(config, provider:, chat_history: nil, memory: nil, tools_registry: nil, tool_policy: nil, prompt_pipeline: nil, token_counter: nil)
      build do |b|
        b.load_config(config)
        b.provider = provider
        b.chat_history = chat_history
        b.memory = memory
        b.tools_registry = tools_registry
        b.tool_policy = tool_policy
        b.prompt_pipeline = prompt_pipeline
        b.token_counter = token_counter
      end
    end

    # @api private
    def initialize(builder:)
      # Identity (serializable)
      @name = builder.name
      @description = builder.description
      @system_prompt = builder.system_prompt
      @model = builder.model
      @max_turns = builder.max_turns

      # Runtime dependencies
      @provider = builder.provider
      @chat_history = builder.chat_history || Resources::ChatHistory::InMemory.new
      @memory = builder.memory
      @tools_registry = builder.tools_registry || Resources::Tools::Registry.new
      @tool_policy = builder.tool_policy
      @skills_store = builder.skills_store
      @include_skill_locations = builder.include_skill_locations == true
      @prompt_pipeline = builder.prompt_pipeline || PromptBuilder::SimplePipeline.new
      @on_event = builder.on_event
      @token_counter = builder.token_counter
      @context_window = builder.context_window
      @reserved_output_tokens = builder.reserved_output_tokens || 0

      # Internal
      @runner = PromptRunner::Runner.new
      @llm_options = builder.llm_options
    end

    # Send a message and get a response (synchronous).
    #
    # @param message [String] User message
    # @param context [ExecutionContext, Hash, nil] Execution context (user/session attributes, etc.)
    # @param instrumenter [Observability::Instrumenter, nil] Optional instrumenter override
    # @param events [PromptRunner::Events, nil] Optional event callbacks
    # @return [PromptRunner::RunResult]
    def chat(message, context: nil, instrumenter: nil, events: nil)
      events = build_events(events)
      execution_context = ExecutionContext.from(context, instrumenter: instrumenter)

      # 1. Build prompt
      prompt = build_prompt(user_message: message, execution_context: execution_context)

      # 2. Run prompt (handles tool loop)
      result = @runner.run(
        prompt: prompt,
        provider: provider,
        tools_registry: tools_registry,
        tool_policy: tool_policy,
        max_turns: max_turns,
        events: events,
        token_counter: token_counter,
        context_window: context_window,
        reserved_output_tokens: reserved_output_tokens,
        context: execution_context
      )

      # 3. Update chat history with new messages
      # Add user message first (if not already in history from build_prompt)
      chat_history.append(Message.new(role: :user, content: message))
      result.messages.each { |msg| chat_history.append(msg) }

      result
    end

    # Send a message with streaming response.
    #
    # @param message [String] User message
    # @param context [ExecutionContext, Hash, nil] Execution context (user/session attributes, etc.)
    # @param instrumenter [Observability::Instrumenter, nil] Optional instrumenter override
    # @param events [PromptRunner::Events, nil] Optional event callbacks
    # @yield [StreamEvent] Stream events
    # @return [PromptRunner::RunResult]
    def chat_stream(message, context: nil, instrumenter: nil, events: nil, &block)
      events = build_events(events)
      execution_context = ExecutionContext.from(context, instrumenter: instrumenter)

      prompt = build_prompt(user_message: message, execution_context: execution_context)

      result = @runner.run_stream(
        prompt: prompt,
        provider: provider,
        tools_registry: tools_registry,
        tool_policy: tool_policy,
        max_turns: max_turns,
        events: events,
        token_counter: token_counter,
        context_window: context_window,
        reserved_output_tokens: reserved_output_tokens,
        context: execution_context,
        &block
      )

      chat_history.append(Message.new(role: :user, content: message))
      result.messages.each { |msg| chat_history.append(msg) }

      result
    end

    # Export the agent's serializable config.
    # Uses the same flat format as Builder#to_config so that
    # Agent.from_config(agent.to_config, ...) round-trips correctly.
    # @return [Hash]
    def to_config
      config = {
        name: name,
        description: description,
        system_prompt: system_prompt,
        model: model,
        max_turns: max_turns,
      }
      # Include LLM options at top level (same as Builder#to_config)
      config[:temperature] = @llm_options[:temperature] if @llm_options[:temperature]
      config[:max_tokens] = @llm_options[:max_tokens] if @llm_options[:max_tokens]
      config[:top_p] = @llm_options[:top_p] if @llm_options[:top_p]
      config[:stop_sequences] = @llm_options[:stop_sequences] if @llm_options[:stop_sequences]
      config[:context_window] = context_window if context_window
      config[:reserved_output_tokens] = reserved_output_tokens if reserved_output_tokens.nonzero?
      config.compact
    end

    # Reset the conversation (clear history).
    def reset!
      chat_history.clear
      self
    end

    private

    def build_prompt(user_message:, execution_context:)
      # Query memory for relevant context
      memory_results = if memory && user_message
        memory.search(query: user_message)
      else
        []
      end

      context = PromptBuilder::Context.new(
        system_prompt: system_prompt,
        chat_history: chat_history,
        tools_registry: tools_registry,
        memory_results: memory_results,
        user_message: user_message,
        variables: {},
        agent_config: { llm_options: @llm_options },
        tool_policy: tool_policy,
        execution_context: execution_context,
        skills_store: skills_store,
        include_skill_locations: include_skill_locations,
      )

      prompt_pipeline.build(context: context)
    end

    def build_events(events)
      events ||= PromptRunner::Events.new

      # Wire up the on_event callback if provided
      if @on_event
        PromptRunner::Events::HOOKS.each do |hook|
          events.on(hook) { |*args| @on_event.call(hook, *args) }
        end
      end

      events
    end
  end
end
