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

      # Runtime dependencies (not serialized)
      attr_accessor :provider, :chat_history, :memory,
                    :tools_registry, :tool_policy,
                    :prompt_pipeline, :on_event

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

        # Runtime
        @provider = nil
        @chat_history = nil
        @memory = nil
        @tools_registry = nil
        @tool_policy = nil
        @prompt_pipeline = nil
        @on_event = nil
      end

      # Build the Agent instance.
      # @return [Agent]
      def build
        validate!
        Agent.new(builder: self)
      end

      # Export serializable config as a Hash.
      # @return [Hash]
      def to_config
        {
          name: name,
          description: description,
          system_prompt: system_prompt,
          model: model,
          temperature: temperature,
          max_tokens: max_tokens,
          top_p: top_p,
          stop_sequences: stop_sequences,
          max_turns: max_turns
        }.compact
      end

      # Load config from a Hash, merging with runtime deps.
      # @param config [Hash]
      # @return [self]
      def load_config(config)
        h = config.transform_keys(&:to_sym)
        @name = h[:name] if h.key?(:name)
        @description = h[:description] if h.key?(:description)
        @system_prompt = h[:system_prompt] if h.key?(:system_prompt)
        @model = h[:model] if h.key?(:model)
        @temperature = h[:temperature] if h.key?(:temperature)
        @max_tokens = h[:max_tokens] if h.key?(:max_tokens)
        @top_p = h[:top_p] if h.key?(:top_p)
        @stop_sequences = h[:stop_sequences] if h.key?(:stop_sequences)
        @max_turns = h[:max_turns] if h.key?(:max_turns)
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
      end
    end
  end
end
