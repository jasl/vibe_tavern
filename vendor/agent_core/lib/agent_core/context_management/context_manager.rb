# frozen_string_literal: true

require_relative "summarizer"

module AgentCore
  module ContextManagement
    class ContextManager
      SUMMARY_MESSAGE_TAG = "<conversation_summary>"
      SUMMARY_MESSAGE_END_TAG = "</conversation_summary>"

      DEFAULT_MEMORY_SEARCH_LIMIT = 5
      DEFAULT_SUMMARY_MAX_OUTPUT_TOKENS = 512
      DEFAULT_MAX_TURNS_TO_DROP_PER_COMPACTION = 20
      DEFAULT_MAX_SUMMARY_BYTES = 20_000

      def initialize(
        agent:,
        conversation_state:,
        token_counter: nil,
        context_window: nil,
        reserved_output_tokens: 0,
        memory_search_limit: DEFAULT_MEMORY_SEARCH_LIMIT,
        summary_max_output_tokens: DEFAULT_SUMMARY_MAX_OUTPUT_TOKENS,
        auto_compact: true,
        clock: Time
      )
        @agent = agent
        @conversation_state = Resources::ConversationState.wrap(conversation_state)
        @token_counter = token_counter
        @context_window = context_window
        @reserved_output_tokens = Integer(reserved_output_tokens || 0, exception: false) || 0
        @memory_search_limit = Integer(memory_search_limit || DEFAULT_MEMORY_SEARCH_LIMIT, exception: false) || DEFAULT_MEMORY_SEARCH_LIMIT
        @memory_search_limit = DEFAULT_MEMORY_SEARCH_LIMIT if @memory_search_limit <= 0
        @summary_max_output_tokens = Integer(summary_max_output_tokens || DEFAULT_SUMMARY_MAX_OUTPUT_TOKENS, exception: false) || DEFAULT_SUMMARY_MAX_OUTPUT_TOKENS
        @summary_max_output_tokens = DEFAULT_SUMMARY_MAX_OUTPUT_TOKENS if @summary_max_output_tokens <= 0
        @auto_compact = auto_compact == true
        @clock = clock

        @summarizer = Summarizer.new(provider: @agent.provider, model: @agent.model)
      end

      # Build a prompt that fits within the context window (when configured).
      #
      # This may:
      # - drop older transcript turns (sliding window)
      # - optionally summarize dropped turns into conversation_state (auto_compact)
      # - drop memory results when needed
      #
      # @return [PromptBuilder::BuiltPrompt]
      def build_prompt(user_message:, execution_context:)
        memory_results = fetch_memory_results(user_message)

        state = safe_load_state
        state = state.with(cursor: 0) if state.summary.nil? && state.cursor.positive?

        base_cursor = state.cursor
        effective_cursor = base_cursor
        effective_summary = state.summary
        effective_compactions = state.compaction_count

        transcript_read = read_messages_after_cursor(@agent.chat_history, base_cursor)
        transcript = transcript_read.fetch(:messages)
        total_messages = transcript_read.fetch(:total_messages)

        if base_cursor > total_messages
          begin
            @conversation_state.clear
          rescue StandardError
            # Ignore persistence errors for stale state cleanup.
          end

          state = Resources::ConversationState::State.new
          base_cursor = 0
          effective_cursor = 0
          effective_summary = nil
          effective_compactions = 0

          transcript_read = read_messages_after_cursor(@agent.chat_history, base_cursor)
          transcript = transcript_read.fetch(:messages)
        end

        turns = split_into_turns(transcript)

        # Fast path: no token budget configured → keep behavior simple.
        unless token_budget_enabled?
          return build_prompt_with(
            summary: effective_summary,
            turns: turns,
            memory_results: memory_results,
            user_message: user_message,
            execution_context: execution_context
          )
        end

        dropped_messages = []
        memory_results = memory_results.dup
        summary_dropped = false

        loop_guard = 0
        max_loops = 200

        loop do
          loop_guard += 1
          raise ContextWindowExceededError, "context management exceeded max_loops=#{max_loops}" if loop_guard > max_loops

          prompt =
            build_prompt_with(
              summary: effective_summary,
              turns: turns,
              memory_results: memory_results,
              user_message: user_message,
              execution_context: execution_context
            )

          est = estimate_prompt_tokens(prompt)
          limit = token_limit

          if est[:estimated_tokens] <= limit
            if @auto_compact && dropped_messages.any?
              begin
                compacted = summarize_messages(previous_summary: effective_summary, messages: dropped_messages)
                effective_summary = compacted
                effective_cursor += dropped_messages.size
                effective_compactions += 1
              rescue StandardError
                # Fallback: keep sliding window only (no state update).
              ensure
                dropped_messages = []
              end

              # Re-check with summary included (summary may add tokens).
              next
            end

            persist_state_if_changed!(
              previous_state: state,
              summary: effective_summary,
              cursor: effective_cursor,
              compaction_count: effective_compactions
            )

            return prompt
          end

          # 1) Drop memory first (keeps conversation coherence)
          if memory_results.any?
            memory_results.pop
            next
          end

          # 2) Drop oldest turns
          if turns.any?
            dropped_turn = turns.shift
            dropped_messages.concat(dropped_turn)

            # Avoid unbounded accumulation on extremely long threads.
            if dropped_messages.size > 0 && dropped_messages.size >= drop_flush_threshold
              if @auto_compact
                begin
                  compacted = summarize_messages(previous_summary: effective_summary, messages: dropped_messages)
                  effective_summary = compacted
                  effective_cursor += dropped_messages.size
                  effective_compactions += 1
                  dropped_messages = []
                rescue StandardError
                  # If summarization fails, keep dropping with sliding window only.
                  dropped_messages = []
                end
              else
                dropped_messages = []
              end
            end

            next
          end

          # 3) Nothing left to drop — the prompt simply cannot fit.
          if !summary_dropped && effective_summary.to_s.strip != ""
            summary_dropped = true
            effective_summary = nil
            effective_cursor = base_cursor
            effective_compactions = state.compaction_count
            dropped_messages = []
            next
          end

          raise ContextWindowExceededError.new(
            estimated_tokens: est[:estimated_tokens],
            message_tokens: est[:message_tokens],
            tool_tokens: est[:tool_tokens],
            context_window: @context_window,
            reserved_output: @reserved_output_tokens,
            limit: limit
          )
        end
      end

      private

      def token_budget_enabled?
        @token_counter && @context_window
      end

      def token_limit
        @context_window - @reserved_output_tokens
      end

      def drop_flush_threshold
        # Prevent summary prompts from growing without bound while still
        # keeping compaction reasonably batched.
        DEFAULT_MAX_TURNS_TO_DROP_PER_COMPACTION * 8
      end

      def safe_load_state
        loaded = @conversation_state.load
        return loaded if loaded.is_a?(Resources::ConversationState::State)

        if loaded.is_a?(Hash)
          h = loaded.transform_keys { |k| k.respond_to?(:to_sym) ? k.to_sym : k }
          return Resources::ConversationState::State.new(
            summary: h[:summary],
            cursor: h[:cursor],
            compaction_count: h[:compaction_count],
            updated_at: h[:updated_at],
          )
        end

        Resources::ConversationState::State.new
      rescue StandardError
        Resources::ConversationState::State.new
      end

      def persist_state_if_changed!(previous_state:, summary:, cursor:, compaction_count:)
        return if previous_state.summary == summary &&
                  previous_state.cursor == cursor &&
                  previous_state.compaction_count == compaction_count

        next_state =
          previous_state.with(
            summary: summary,
            cursor: cursor,
            compaction_count: compaction_count,
            updated_at: @clock.respond_to?(:now) ? @clock.now : nil,
          )

        @conversation_state.save(next_state)
      rescue StandardError
        # Persistence failures should not break the agent loop.
      end

      def fetch_memory_results(user_message)
        mem = @agent.memory
        query = user_message.to_s
        return [] unless mem && !query.strip.empty?

        mem.search(query: query, limit: @memory_search_limit)
      rescue StandardError
        []
      end

      def read_messages_after_cursor(chat_history, cursor)
        cursor = Integer(cursor || 0, exception: false) || 0
        cursor = 0 if cursor.negative?

        out = []
        idx = 0
        chat_history.each do |msg|
          if idx >= cursor
            out << msg
          end
          idx += 1
        end

        { messages: out, total_messages: idx }
      end

      def split_into_turns(messages)
        turns = []
        current = []

        messages.each do |msg|
          if msg.user? && current.any?
            turns << current
            current = []
          end
          current << msg
        end

        turns << current if current.any?
        turns
      end

      def build_prompt_with(summary:, turns:, memory_results:, user_message:, execution_context:)
        history_messages = turns.flatten

        if (s = summary.to_s).strip != ""
          history_messages = [summary_message(s)] + history_messages
        end

        history_view = Resources::ChatHistory::InMemory.new(history_messages)

        context =
          PromptBuilder::Context.new(
            system_prompt: @agent.system_prompt,
            chat_history: history_view,
            tools_registry: @agent.tools_registry,
            memory_results: memory_results,
            user_message: user_message,
            variables: {},
            agent_config: { llm_options: @agent.llm_options },
            tool_policy: @agent.tool_policy,
            execution_context: execution_context,
            skills_store: @agent.skills_store,
            include_skill_locations: @agent.include_skill_locations,
          )

        @agent.prompt_pipeline.build(context: context)
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

      def sanitize_for_summary(messages)
        max_text_bytes = 4_000
        max_tool_bytes = 8_000

        messages.filter_map do |msg|
          next if msg.system?

          role = msg.role.to_s
          body =
            case msg.role
            when :tool_result
              name = msg.name.to_s
              id = msg.tool_call_id.to_s
              content = Utils.truncate_utf8_bytes(msg.text, max_bytes: max_tool_bytes)
              "[tool_result name=#{name} id=#{id}] #{content}"
            else
              content = Utils.truncate_utf8_bytes(msg.text, max_bytes: max_text_bytes)
              if msg.assistant? && msg.has_tool_calls?
                tool_names = msg.tool_calls.map(&:name).uniq
                "[#{role}] #{content}\n[tool_calls] #{tool_names.join(", ")}"
              else
                "[#{role}] #{content}"
              end
            end

          body.strip
        end
      end

      def summarize_messages(previous_summary:, messages:)
        sanitized_lines = sanitize_for_summary(messages)
        transcript = sanitized_lines.join("\n")

        @summarizer.summarize(
          previous_summary: previous_summary,
          transcript: transcript,
          max_output_tokens: @summary_max_output_tokens
        )
      end

      def estimate_prompt_tokens(prompt)
        msgs = prompt.messages.dup
        sys = prompt.system_prompt.to_s
        msgs.unshift(Message.new(role: :system, content: sys)) unless sys.empty?

        msg_tokens = @token_counter.count_messages(msgs)
        tool_tokens = prompt.tools && !prompt.tools.empty? ? @token_counter.count_tools(prompt.tools) : 0

        {
          estimated_tokens: msg_tokens + tool_tokens,
          message_tokens: msg_tokens,
          tool_tokens: tool_tokens,
        }
      end
    end
  end
end
