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
                :token_counter, :context_window, :reserved_output_tokens,
                :conversation_state, :auto_compact, :memory_search_limit,
                :summary_max_output_tokens, :llm_options,
                :prompt_injection_sources

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
    def self.from_config(config, provider:, chat_history: nil, memory: nil, conversation_state: nil,
                         tools_registry: nil, tool_policy: nil, prompt_pipeline: nil, token_counter: nil,
                         prompt_injection_text_store: nil)
      build do |b|
        b.load_config(config)
        b.provider = provider
        b.chat_history = chat_history
        b.memory = memory
        b.conversation_state = conversation_state
        b.tools_registry = tools_registry
        b.tool_policy = tool_policy
        b.prompt_pipeline = prompt_pipeline
        b.token_counter = token_counter
        b.prompt_injection_text_store = prompt_injection_text_store
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
      @auto_compact = builder.auto_compact == true
      @memory_search_limit = builder.memory_search_limit
      @summary_max_output_tokens = builder.summary_max_output_tokens

      # Runtime dependencies
      @provider = builder.provider
      @chat_history = builder.chat_history || Resources::ChatHistory::InMemory.new
      @memory = builder.memory
      @conversation_state = Resources::ConversationState.wrap(builder.conversation_state)
      @tools_registry = builder.tools_registry || Resources::Tools::Registry.new
      @tool_policy = builder.tool_policy
      @skills_store = builder.skills_store
      @include_skill_locations = builder.include_skill_locations == true
      @prompt_pipeline = builder.prompt_pipeline || PromptBuilder::SimplePipeline.new
      @on_event = builder.on_event
      @token_counter = builder.token_counter
      @context_window = builder.context_window
      @reserved_output_tokens = builder.reserved_output_tokens || 0
      @tool_executor = builder.tool_executor

      @prompt_injection_source_specs = Array(builder.prompt_injection_source_specs)
      @prompt_injection_sources =
        Resources::PromptInjections::Factory.build_sources(
          specs: @prompt_injection_source_specs,
          text_store: builder.prompt_injection_text_store
        ).freeze

      # Internal
      @runner = PromptRunner::Runner.new
      @llm_options = builder.llm_options
      @llm_options.freeze
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
        tool_executor: @tool_executor,
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
        tool_executor: @tool_executor,
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

    # Resume a paused run after providing tool confirmations.
    #
    # @param continuation [PromptRunner::Continuation, PromptRunner::RunResult] RunResult or continuation token
    # @param tool_confirmations [Hash{String=>Symbol,Boolean}] tool_call_id => :allow/:deny (or true/false)
    # @return [PromptRunner::RunResult]
    def resume(continuation:, tool_confirmations:, context: nil, instrumenter: nil, events: nil)
      events = build_events(events)
      execution_context = ExecutionContext.from(context, instrumenter: instrumenter)

      cont = normalize_continuation!(continuation)

      result =
        @runner.resume(
          continuation: cont,
          tool_confirmations: tool_confirmations,
          provider: provider,
          tools_registry: tools_registry,
          tool_policy: tool_policy,
          tool_executor: @tool_executor,
          token_counter: token_counter,
          context_window: context_window,
          reserved_output_tokens: reserved_output_tokens,
          context: execution_context,
          events: events,
        )

      result.messages.each { |msg| chat_history.append(msg) }
      result
    end

    # Resume a paused run with streaming events.
    def resume_stream(continuation:, tool_confirmations:, context: nil, instrumenter: nil, events: nil, &block)
      events = build_events(events)
      execution_context = ExecutionContext.from(context, instrumenter: instrumenter)

      cont = normalize_continuation!(continuation)

      result =
        @runner.resume_stream(
          continuation: cont,
          tool_confirmations: tool_confirmations,
          provider: provider,
          tools_registry: tools_registry,
          tool_policy: tool_policy,
          tool_executor: @tool_executor,
          token_counter: token_counter,
          context_window: context_window,
          reserved_output_tokens: reserved_output_tokens,
          context: execution_context,
          events: events,
          &block
        )

      result.messages.each { |msg| chat_history.append(msg) }
      result
    end

    # Resume a paused run after receiving external tool execution results.
    def resume_with_tool_results(continuation:, tool_results:, context: nil, instrumenter: nil, events: nil, allow_partial: false)
      events = build_events(events)
      execution_context = ExecutionContext.from(context, instrumenter: instrumenter)

      cont = normalize_continuation!(continuation)

      result =
        @runner.resume_with_tool_results(
          continuation: cont,
          tool_results: tool_results,
          provider: provider,
          tools_registry: tools_registry,
          tool_policy: tool_policy,
          tool_executor: @tool_executor,
          token_counter: token_counter,
          context_window: context_window,
          reserved_output_tokens: reserved_output_tokens,
          context: execution_context,
          events: events,
          allow_partial: allow_partial,
        )

      result.messages.each { |msg| chat_history.append(msg) }
      result
    end

    # Streaming variant of {#resume_with_tool_results}.
    def resume_stream_with_tool_results(continuation:, tool_results:, context: nil, instrumenter: nil, events: nil, allow_partial: false, &block)
      events = build_events(events)
      execution_context = ExecutionContext.from(context, instrumenter: instrumenter)

      cont = normalize_continuation!(continuation)

      result =
        @runner.resume_stream_with_tool_results(
          continuation: cont,
          tool_results: tool_results,
          provider: provider,
          tools_registry: tools_registry,
          tool_policy: tool_policy,
          tool_executor: @tool_executor,
          token_counter: token_counter,
          context_window: context_window,
          reserved_output_tokens: reserved_output_tokens,
          context: execution_context,
          events: events,
          allow_partial: allow_partial,
          &block
        )

      result.messages.each { |msg| chat_history.append(msg) }
      result
    end

    # Export the agent's structured serializable config (versioned).
    # @return [Hash]
    def to_config(only: nil, except: nil)
      b = Builder.new

      b.name = name
      b.description = description
      b.system_prompt = system_prompt
      b.model = model
      b.temperature = @llm_options[:temperature]
      b.max_tokens = @llm_options[:max_tokens]
      b.top_p = @llm_options[:top_p]
      b.stop_sequences = @llm_options[:stop_sequences]
      b.max_turns = max_turns

      b.context_window = context_window
      b.reserved_output_tokens = reserved_output_tokens

      b.auto_compact = auto_compact
      b.memory_search_limit = memory_search_limit
      b.summary_max_output_tokens = summary_max_output_tokens

      b.prompt_injection_source_specs = @prompt_injection_source_specs

      b.to_config(only: only, except: except)
    end

    # Reset the conversation (clear history).
    def reset!
      chat_history.clear
      conversation_state.clear
      self
    end

    private

    SUMMARY_MESSAGE_TAG = "<conversation_summary>"
    SUMMARY_MESSAGE_END_TAG = "</conversation_summary>"

    DEFAULT_MEMORY_SEARCH_LIMIT = 5
    DEFAULT_MAX_SUMMARY_BYTES = 20_000

    def build_prompt(user_message:, execution_context:)
      prompt_mode = resolve_prompt_mode(execution_context)
      prompt_injection_items =
        collect_prompt_injection_items(
          user_message: user_message,
          execution_context: execution_context,
          prompt_mode: prompt_mode
        )

      memory_results = fetch_memory_results(user_message)

      budget_manager =
        ContextManagement::BudgetManager.new(
          chat_history: chat_history,
          conversation_state: conversation_state,
          provider: provider,
          model: model,
          token_counter: token_counter,
          context_window: context_window,
          reserved_output_tokens: reserved_output_tokens,
          summary_max_output_tokens: summary_max_output_tokens,
          auto_compact: auto_compact,
        )

      budget_manager.build_prompt(memory_results: memory_results) do |summary:, turns:, memory_results:|
        build_prompt_with(
          summary: summary,
          turns: turns,
          memory_results: memory_results,
          user_message: user_message,
          execution_context: execution_context,
          prompt_mode: prompt_mode,
          prompt_injection_items: prompt_injection_items
        )
      end
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

    def normalize_continuation!(value)
      case value
      when PromptRunner::Continuation
        value
      when PromptRunner::RunResult
        cont = value.continuation
        raise ArgumentError, "run_result has no continuation" unless cont
        cont
      when Hash, String
        value
      else
        raise ArgumentError, "continuation must be a PromptRunner::Continuation, PromptRunner::RunResult, Hash, or JSON String (got #{value.class})"
      end
    end

    def resolve_prompt_mode(execution_context)
      mode = execution_context.attributes.fetch(:prompt_mode, :full)
      mode = mode.to_sym
      return mode if mode == :full || mode == :minimal

      :full
    rescue StandardError
      :full
    end

    def collect_prompt_injection_items(user_message:, execution_context:, prompt_mode:)
      sources = Array(prompt_injection_sources)
      return [] if sources.empty?

      items =
        sources.flat_map do |source|
          next [] unless source

          begin
            Array(
              source.items(
                agent: self,
                user_message: user_message,
                execution_context: execution_context,
                prompt_mode: prompt_mode
              )
            )
          rescue StandardError
            []
          end
        end

      items
        .select { |item| item.is_a?(Resources::PromptInjections::Item) }
        .select { |item| item.allowed_in_prompt_mode?(prompt_mode) }
    rescue StandardError
      []
    end

    def fetch_memory_results(user_message)
      mem = memory
      query = user_message.to_s
      return [] unless mem && !query.strip.empty?

      limit = Integer(memory_search_limit || DEFAULT_MEMORY_SEARCH_LIMIT, exception: false) || DEFAULT_MEMORY_SEARCH_LIMIT
      limit = DEFAULT_MEMORY_SEARCH_LIMIT if limit <= 0

      mem.search(query: query, limit: limit)
    rescue StandardError
      []
    end

    def build_prompt_with(summary:, turns:, memory_results:, user_message:, execution_context:, prompt_mode:, prompt_injection_items:)
      history_messages = turns.flatten

      if (s = summary.to_s).strip != ""
        history_messages = [summary_message(s)] + history_messages
      end

      history_view = Resources::ChatHistory::InMemory.new(history_messages)

      context =
        PromptBuilder::Context.new(
          system_prompt: system_prompt,
          chat_history: history_view,
          tools_registry: tools_registry,
          memory_results: memory_results,
          user_message: user_message,
          variables: {},
          agent_config: { llm_options: llm_options },
          tool_policy: tool_policy,
          execution_context: execution_context,
          skills_store: skills_store,
          include_skill_locations: include_skill_locations,
          prompt_mode: prompt_mode,
          prompt_injection_items: prompt_injection_items,
        )

      prompt_pipeline.build(context: context)
    end

    def summary_message(text)
      safe = Utils.truncate_utf8_bytes(text.to_s.strip, max_bytes: DEFAULT_MAX_SUMMARY_BYTES)
      wrapped = "#{SUMMARY_MESSAGE_TAG}\n#{safe}\n#{SUMMARY_MESSAGE_END_TAG}"

      Message.new(
        role: :assistant,
        content: wrapped,
        metadata: { kind: "conversation_summary" }
      )
    end
  end
end
