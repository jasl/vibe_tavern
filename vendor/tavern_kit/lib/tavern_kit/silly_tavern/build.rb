# frozen_string_literal: true

require_relative "pipeline"

module TavernKit
  module SillyTavern
    class << self
      # Convenience entrypoint using the default SillyTavern pipeline.
      #
      # This is the primary way downstream applications should construct ST-like
      # prompts, while still allowing per-call pipeline customization via the DSL.
      def build(**kwargs, &block)
        TavernKit::PromptBuilder.build(pipeline: Pipeline, **kwargs, &block)
      end

      def to_messages(dialect: :openai, **kwargs, &block)
        TavernKit.to_messages(dialect: dialect, pipeline: Pipeline, **kwargs, &block)
      end
    end
  end
end
