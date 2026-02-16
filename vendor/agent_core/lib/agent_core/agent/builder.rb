# frozen_string_literal: true

module AgentCore
  class Agent
    # Builder for constructing Agent instances.
    #
    # Separates serializable config (identity, model prefs) from
    # runtime dependencies (provider, history, tools).
    class Builder
      # Serializable fields (identity + model preferences)
      attr_accessor :name, :description, :system_prompt,
                    :model, :temperature, :max_tokens, :top_p,
                    :stop_sequences, :max_turns

      # Context management (serializable)
      attr_accessor :auto_compact, :memory_search_limit, :summary_max_output_tokens

      # Prompt injections (serializable)
      attr_accessor :prompt_injection_source_specs

      # Runtime dependencies (not serialized)
      attr_accessor :provider, :chat_history, :memory,
                    :tools_registry, :tool_policy,
                    :skills_store, :include_skill_locations,
                    :prompt_pipeline, :on_event,
                    :token_counter, :tool_executor,
                    :conversation_state,
                    :prompt_injection_text_store

      # Token budget (serializable)
      attr_accessor :context_window, :reserved_output_tokens

      CONFIG_VERSION = 1

      CONFIG_GROUPS =
        [
          :identity,
          :llm,
          :execution,
          :token_budget,
          :context_management,
          :prompt_injections,
        ].freeze

      def initialize
        # Defaults
        @name = "Agent"
        @description = ""
        @system_prompt = "You are a helpful assistant."
        @model = nil
        @temperature = nil
        @max_tokens = nil
        @top_p = nil
        @stop_sequences = nil
        @max_turns = 10

        # Context management
        @auto_compact = true
        @memory_search_limit = nil
        @summary_max_output_tokens = nil

        # Token budget
        @context_window = nil
        @reserved_output_tokens = 0

        # Prompt injections
        @prompt_injection_source_specs = []

        # Runtime
        @provider = nil
        @chat_history = nil
        @memory = nil
        @conversation_state = nil
        @tools_registry = nil
        @tool_policy = Resources::Tools::Policy::DenyAll.new
        @skills_store = nil
        @include_skill_locations = false
        @prompt_pipeline = nil
        @on_event = nil
        @token_counter = nil
        @tool_executor = PromptRunner::ToolExecutor::Inline.new
        @prompt_injection_text_store = nil
      end

      # Build the Agent instance.
      # @return [Agent]
      def build
        validate!
        Agent.new(builder: self)
      end

      # Export serializable config as a Hash.
      # @return [Hash]
      def to_config(only: nil, except: nil)
        full = {
          version: CONFIG_VERSION,
          identity: {
            name: name,
            description: description,
            system_prompt: system_prompt,
          }.compact,
          llm: {
            model: model,
            options: {
              temperature: temperature,
              max_tokens: max_tokens,
              top_p: top_p,
              stop_sequences: stop_sequences,
            }.compact,
          }.compact,
          execution: {
            max_turns: max_turns,
          }.compact,
          token_budget: {
            context_window: context_window,
            reserved_output_tokens: reserved_output_tokens || 0,
          }.compact,
          context_management: {
            auto_compact: auto_compact == true,
            memory_search_limit: memory_search_limit,
            summary_max_output_tokens: summary_max_output_tokens,
          }.compact,
          prompt_injections: {
            sources: Array(prompt_injection_source_specs),
          },
        }

        apply_group_selection(full, only: only, except: except)
      end

      # Load config from a Hash, merging with runtime deps.
      # @param config [Hash]
      # @return [self]
      def load_config(config)
        h = AgentCore::Utils.deep_symbolize_keys(config)
        version = h[:version]
        raise ConfigurationError, "config version must be #{CONFIG_VERSION} (got #{version.inspect})" unless version == CONFIG_VERSION

        if (identity = h[:identity]).is_a?(Hash)
          @name = identity[:name] if identity.key?(:name)
          @description = identity[:description] if identity.key?(:description)
          @system_prompt = identity[:system_prompt] if identity.key?(:system_prompt)
        end

        if (llm = h[:llm]).is_a?(Hash)
          @model = llm[:model] if llm.key?(:model)
          opts = llm[:options].is_a?(Hash) ? llm[:options] : {}
          @temperature = opts[:temperature] if opts.key?(:temperature)
          @max_tokens = opts[:max_tokens] if opts.key?(:max_tokens)
          @top_p = opts[:top_p] if opts.key?(:top_p)
          @stop_sequences = opts[:stop_sequences] if opts.key?(:stop_sequences)
        end

        if (execution = h[:execution]).is_a?(Hash)
          @max_turns = execution[:max_turns] if execution.key?(:max_turns)
        end

        if (budget = h[:token_budget]).is_a?(Hash)
          @context_window = budget[:context_window] if budget.key?(:context_window)
          @reserved_output_tokens = budget[:reserved_output_tokens] || 0 if budget.key?(:reserved_output_tokens)
        end

        if (cm = h[:context_management]).is_a?(Hash)
          @auto_compact = cm[:auto_compact] unless cm[:auto_compact].nil?
          @memory_search_limit = cm[:memory_search_limit] if cm.key?(:memory_search_limit)
          @summary_max_output_tokens = cm[:summary_max_output_tokens] if cm.key?(:summary_max_output_tokens)
        end

        if (pi = h[:prompt_injections]).is_a?(Hash)
          sources = pi[:sources]
          @prompt_injection_source_specs = sources.is_a?(Array) ? sources : []
        end

        self
      end

      # LLM options hash for the prompt builder.
      def llm_options
        opts = {}
        opts[:model] = model if model
        opts[:temperature] = temperature if temperature
        opts[:max_tokens] = max_tokens if max_tokens
        opts[:top_p] = top_p if top_p
        opts[:stop_sequences] = stop_sequences if stop_sequences
        opts
      end

      private

      def validate!
        raise ConfigurationError, "provider is required" unless provider

        if context_window
          unless context_window.is_a?(Integer) && context_window.positive?
            raise ConfigurationError, "context_window must be a positive Integer (got #{context_window.inspect})"
          end
        end

        rot = reserved_output_tokens || 0
        unless rot.is_a?(Integer) && rot >= 0
          raise ConfigurationError, "reserved_output_tokens must be a non-negative Integer (got #{rot.inspect})"
        end

        if context_window && rot >= context_window
          raise ConfigurationError, "reserved_output_tokens must be less than context_window " \
                                    "(got reserved_output_tokens=#{rot}, context_window=#{context_window})"
        end

        if token_counter
          unless token_counter.respond_to?(:count_messages) && token_counter.respond_to?(:count_tools)
            raise ConfigurationError, "token_counter must respond to #count_messages and #count_tools"
          end
        end

        if memory_search_limit
          parsed = Integer(memory_search_limit, exception: false)
          raise ConfigurationError, "memory_search_limit must be a positive Integer" if parsed.nil? || parsed <= 0
        end

        if summary_max_output_tokens
          parsed = Integer(summary_max_output_tokens, exception: false)
          raise ConfigurationError, "summary_max_output_tokens must be a positive Integer" if parsed.nil? || parsed <= 0
        end

        if prompt_injection_text_store && !prompt_injection_text_store.respond_to?(:fetch)
          raise ConfigurationError, "prompt_injection_text_store must respond to #fetch(key:) (got #{prompt_injection_text_store.class})"
        end
      end

      def apply_group_selection(full, only:, except:)
        if only && except
          raise ArgumentError, "only and except cannot both be provided"
        end

        if only
          groups = normalize_groups!(only)
          out = { version: full.fetch(:version) }
          groups.each { |g| out[g] = full[g] }
          return out
        end

        if except
          groups = normalize_groups!(except)
          out = full.dup
          groups.each { |g| out.delete(g) }
          return out
        end

        full
      end

      def normalize_groups!(value)
        groups = Array(value).map(&:to_sym)
        unknown = groups - CONFIG_GROUPS
        raise ArgumentError, "Unknown config group(s): #{unknown.inspect}" if unknown.any?
        groups
      end
    end
  end
end
