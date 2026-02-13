# frozen_string_literal: true

module AgentCore
  module PromptBuilder
    # Abstract prompt-building pipeline.
    #
    # The pipeline takes a Context and produces a BuiltPrompt. Implementations
    # can range from simple (direct assembly) to complex (ST-style macro
    # expansion, injection planning, context templates).
    #
    # The pipeline is an interface — swap it to change how prompts are built
    # without touching the rest of the system.
    class Pipeline
      # Build a prompt from the given context.
      #
      # @param context [Context] All data sources for prompt building
      # @return [BuiltPrompt]
      def build(context:)
        raise AgentCore::NotImplementedError, "#{self.class}#build must be implemented"
      end
    end
  end
end
