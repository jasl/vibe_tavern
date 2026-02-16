# frozen_string_literal: true

require_relative "directives"
require_relative "language_policy"
require_relative "openai"
require_relative "openai_history"
require_relative "provider_with_defaults"

module AgentCore
  module Contrib
    class AgentSession
      def initialize(
        provider:,
        model:,
        system_prompt:,
        history: nil,
        llm_options: {},
        token_counter: nil,
        context_window: nil,
        reserved_output_tokens: 0,
        max_turns: 10,
        tools_registry: nil,
        tool_policy: nil,
        tool_executor: nil,
        directives_config: {},
        capabilities: {}
      )
        @base_provider = provider
        @model = model.to_s.strip
        raise ArgumentError, "model is required" if @model.empty?

        @system_prompt = system_prompt.to_s
        @llm_options = normalize_llm_options(llm_options).freeze
        @token_counter = token_counter
        @context_window = normalize_context_window(context_window)
        @reserved_output_tokens = Integer(reserved_output_tokens || 0, exception: false) || 0
        @reserved_output_tokens = 0 if @reserved_output_tokens.negative?
        if @context_window && @reserved_output_tokens >= @context_window
          raise ArgumentError, "reserved_output_tokens must be less than context_window " \
                               "(got reserved_output_tokens=#{@reserved_output_tokens}, context_window=#{@context_window})"
        end

        @max_turns = Integer(max_turns || 10, exception: false) || 10
        raise ArgumentError, "max_turns must be >= 1" if @max_turns < 1

        @tools_registry = tools_registry
        @tool_policy = tool_policy
        @tool_executor = tool_executor
        @directives_config = directives_config.is_a?(Hash) ? AgentCore::Utils.deep_symbolize_keys(directives_config) : {}
        @capabilities = capabilities.is_a?(Hash) ? AgentCore::Utils.deep_symbolize_keys(capabilities) : {}

        @chat_history = AgentCore::Resources::ChatHistory::InMemory.new
        AgentCore::Contrib::OpenAIHistory.coerce_messages(history).each { |m| @chat_history.append(m) }

        @provider_with_defaults =
          AgentCore::Contrib::ProviderWithDefaults.new(
            provider: @base_provider,
            request_defaults: @llm_options,
          )

        @agent = build_agent
      end

      def chat(user_text = nil, language_policy: nil, context: nil)
        text = user_text.to_s

        run_result =
          if text.strip.empty?
            run_history_only(context: context)
          else
            @agent.chat(text, context: context)
          end

        apply_language_policy_to_run_result(run_result, language_policy: language_policy)
      end

      def chat_stream(user_text = nil, language_policy: nil, context: nil, &block)
        policy = normalize_language_policy(language_policy)

        if policy.fetch(:enabled) && policy.fetch(:target_lang, nil)
          result = chat(user_text, language_policy: policy, context: context)
          emit_final_only_stream_events(result, &block)
          return result
        end

        text = user_text.to_s
        if text.strip.empty?
          result = run_history_only(context: context)
          emit_final_only_stream_events(result, &block)
          return result
        end

        @agent.chat_stream(text, context: context, &block)
      end

      def resume(continuation:, tool_confirmations:, language_policy: nil, context: nil)
        run_result = @agent.resume(continuation: continuation, tool_confirmations: tool_confirmations, context: context)
        apply_language_policy_to_run_result(run_result, language_policy: language_policy)
      end

      def resume_stream(continuation:, tool_confirmations:, language_policy: nil, context: nil, &block)
        policy = normalize_language_policy(language_policy)

        if policy.fetch(:enabled) && policy.fetch(:target_lang, nil)
          result = resume(continuation: continuation, tool_confirmations: tool_confirmations, language_policy: policy, context: context)
          emit_final_only_stream_events(result, &block)
          return result
        end

        @agent.resume_stream(continuation: continuation, tool_confirmations: tool_confirmations, context: context, &block)
      end

      def resume_with_tool_results(continuation:, tool_results:, language_policy: nil, allow_partial: false, context: nil)
        run_result = @agent.resume_with_tool_results(continuation: continuation, tool_results: tool_results, allow_partial: allow_partial, context: context)
        apply_language_policy_to_run_result(run_result, language_policy: language_policy)
      end

      def resume_stream_with_tool_results(continuation:, tool_results:, language_policy: nil, allow_partial: false, context: nil, &block)
        policy = normalize_language_policy(language_policy)

        if policy.fetch(:enabled) && policy.fetch(:target_lang, nil)
          result = resume_with_tool_results(continuation: continuation, tool_results: tool_results, language_policy: policy, allow_partial: allow_partial, context: context)
          emit_final_only_stream_events(result, &block)
          return result
        end

        @agent.resume_stream_with_tool_results(continuation: continuation, tool_results: tool_results, allow_partial: allow_partial, context: context, &block)
      end

      def directives(language_policy: nil, structured_output_options: nil, result_validator: nil)
        policy = normalize_language_policy(language_policy)

        directives_runner =
          AgentCore::Contrib::Directives::Runner.new(
            provider: @base_provider,
            model: @model,
            llm_options_defaults: @llm_options,
            directives_config: @directives_config,
            capabilities: @capabilities,
          )

        result =
          directives_runner.run(
            history: @chat_history.each.to_a,
            system: @system_prompt,
            structured_output_options: structured_output_options,
            result_validator: result_validator,
            token_counter: @token_counter,
            context_window: @context_window,
            reserved_output_tokens: @reserved_output_tokens,
          )

        return result unless result.is_a?(Hash)
        return result unless result.fetch(:ok, false) == true
        return result unless policy.fetch(:enabled) && policy.fetch(:target_lang, nil)

        assistant_text = result.fetch(:assistant_text, "").to_s
        rewritten = rewrite_text(assistant_text, policy)
        return result if rewritten.to_s.strip.empty? || rewritten == assistant_text

        updated = result.dup
        updated[:assistant_text] = rewritten

        envelope = updated.fetch(:envelope, nil)
        if envelope.is_a?(Hash)
          updated_envelope = envelope.dup
          updated_envelope["assistant_text"] = rewritten
          updated[:envelope] = updated_envelope
        end

        updated
      end

      private

      def build_agent
        llm_options = @llm_options
        AgentCore::Agent.build do |b|
          b.provider = @provider_with_defaults
          b.model = @model
          b.system_prompt = @system_prompt
          b.chat_history = @chat_history
          b.tools_registry = @tools_registry if @tools_registry
          b.tool_policy = @tool_policy if @tool_policy
          b.tool_executor = @tool_executor if @tool_executor
          b.max_turns = @max_turns

          b.token_counter = @token_counter if @token_counter
          b.context_window = @context_window if @context_window
          b.reserved_output_tokens = @reserved_output_tokens if @reserved_output_tokens.positive?

          b.temperature = llm_options[:temperature] if llm_options.key?(:temperature)
          b.max_tokens = llm_options[:max_tokens] if llm_options.key?(:max_tokens)
          b.top_p = llm_options[:top_p] if llm_options.key?(:top_p)
          if llm_options.key?(:stop_sequences)
            b.stop_sequences = llm_options[:stop_sequences]
          elsif llm_options.key?(:stop)
            b.stop_sequences = llm_options[:stop]
          end
        end
      end

      def run_history_only(context:)
        prompt =
          AgentCore::PromptBuilder::BuiltPrompt.new(
            system_prompt: @system_prompt,
            messages: @chat_history.each.to_a,
            tools: [],
            options: { model: @model }.merge(@llm_options),
          )

        AgentCore::PromptRunner::Runner.new.run(
          prompt: prompt,
          provider: @provider_with_defaults,
          tools_registry: @tools_registry,
          tool_policy: @tool_policy,
          max_turns: @max_turns,
          token_counter: @token_counter,
          context_window: @context_window,
          reserved_output_tokens: @reserved_output_tokens,
          context: context,
        )
      end

      def apply_language_policy_to_run_result(run_result, language_policy:)
        policy = normalize_language_policy(language_policy)
        return run_result unless policy.fetch(:enabled) && policy.fetch(:target_lang, nil)

        # Only rewrite when the tool loop has fully completed.
        return run_result if run_result.respond_to?(:awaiting_tool_confirmation?) && run_result.awaiting_tool_confirmation?
        return run_result if run_result.respond_to?(:awaiting_tool_results?) && run_result.awaiting_tool_results?

        final_message = run_result.final_message
        return run_result unless final_message

        original = final_message.text.to_s
        rewritten = rewrite_text(original, policy)
        return run_result if rewritten.to_s.strip.empty? || rewritten == original

        new_metadata =
          if final_message.metadata.is_a?(Hash)
            final_message.metadata.merge(
              language_policy: {
                target_lang: policy.fetch(:target_lang),
                original_text: original,
              },
            )
          else
            {
              language_policy: {
                target_lang: policy.fetch(:target_lang),
                original_text: original,
              },
            }
          end

        new_final_message =
          AgentCore::Message.new(
            role: final_message.role,
            content: rewritten,
            tool_calls: final_message.tool_calls,
            tool_call_id: final_message.tool_call_id,
            name: final_message.name,
            metadata: new_metadata,
          )

        new_messages = replace_message_identity(run_result.messages, final_message, new_final_message)

        # Keep session history consistent with the returned run_result when possible.
        if @chat_history.respond_to?(:replace_message)
          @chat_history.replace_message(final_message, new_final_message)
        end

        AgentCore::PromptRunner::RunResult.new(
          run_id: run_result.run_id,
          started_at: run_result.started_at,
          ended_at: run_result.ended_at,
          duration_ms: run_result.duration_ms,
          messages: new_messages,
          final_message: new_final_message,
          turns: run_result.turns,
          usage: run_result.usage,
          per_turn_usage: run_result.per_turn_usage,
          tool_calls_made: run_result.tool_calls_made,
          stop_reason: run_result.stop_reason,
          trace: run_result.trace,
          pending_tool_confirmations: run_result.pending_tool_confirmations,
          pending_tool_executions: run_result.pending_tool_executions,
          continuation: run_result.continuation,
        )
      end

      def replace_message_identity(messages, target, replacement)
        out = messages.dup
        idx = nil
        (out.length - 1).downto(0) do |i|
          if out[i].equal?(target)
            idx = i
            break
          end
        end
        out[idx] = replacement if idx
        out
      end

      def rewrite_text(text, policy)
        return text.to_s unless policy.fetch(:enabled) && policy.fetch(:target_lang, nil)

        AgentCore::Contrib::LanguagePolicy::FinalRewriter.rewrite(
          provider: @base_provider,
          model: @model,
          text: text.to_s,
          target_lang: policy.fetch(:target_lang),
          style_hint: policy.fetch(:style_hint),
          special_tags: policy.fetch(:special_tags),
          llm_options: rewrite_llm_options,
          token_counter: @token_counter,
          context_window: @context_window,
          reserved_output_tokens: 0,
        )
      end

      def rewrite_llm_options
        out = {}
        out[:max_tokens] = @llm_options[:max_tokens] if @llm_options.key?(:max_tokens)
        out
      end

      def emit_final_only_stream_events(result, &block)
        return result unless block

        final_message = result.final_message || AgentCore::Message.new(role: :assistant, content: "")

        block.call(AgentCore::StreamEvent::TextDelta.new(text: final_message.text.to_s))
        block.call(AgentCore::StreamEvent::MessageComplete.new(message: final_message))
        block.call(AgentCore::StreamEvent::Done.new(stop_reason: result.stop_reason, usage: result.usage))

        result
      end

      def normalize_llm_options(value)
        h = value.nil? ? {} : value
        raise ArgumentError, "llm_options must be a Hash" unless h.is_a?(Hash)

        normalized = AgentCore::Utils.deep_symbolize_keys(h)
        AgentCore::Utils.assert_symbol_keys!(normalized, path: "llm_options")

        reserved = normalized.keys & AgentCore::Contrib::OpenAI::RESERVED_CHAT_COMPLETIONS_KEYS
        if reserved.any?
          raise ArgumentError, "llm_options contains reserved keys: #{reserved.map(&:to_s).sort.inspect}"
        end

        normalized
      end

      def normalize_context_window(value)
        return nil if value.nil?

        parsed = Integer(value, exception: false)
        raise ArgumentError, "context_window must be a positive Integer (got #{value.inspect})" if parsed.nil? || parsed <= 0

        parsed
      end

      def normalize_language_policy(value)
        return { enabled: false, target_lang: nil, style_hint: nil, special_tags: [] } if value.nil?
        raise ArgumentError, "language_policy must be a Hash" unless value.is_a?(Hash)

        cfg = AgentCore::Utils.deep_symbolize_keys(value)

        enabled = cfg.fetch(:enabled, false) == true

        target_lang = cfg.fetch(:target_lang, nil).to_s.strip
        target_lang = nil if target_lang.empty?

        style_hint = cfg.fetch(:style_hint, nil).to_s.strip
        style_hint = nil if style_hint.empty?

        tags =
          Array(cfg.fetch(:special_tags, []))
            .map { |t| t.to_s.strip }
            .reject(&:empty?)
            .uniq

        {
          enabled: enabled,
          target_lang: target_lang,
          style_hint: style_hint,
          special_tags: tags,
        }
      end
    end
  end
end
