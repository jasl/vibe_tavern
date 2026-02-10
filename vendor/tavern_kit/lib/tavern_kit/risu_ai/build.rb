# frozen_string_literal: true

require_relative "pipeline"

module TavernKit
  module RisuAI
    class << self
      # Convenience entrypoint using the default RisuAI pipeline.
      def build(**kwargs, &block)
        TavernKit::PromptBuilder.build(pipeline: Pipeline, **kwargs, &block)
      end

      def to_messages(dialect: :openai, **kwargs, &block)
        TavernKit.to_messages(dialect: dialect, pipeline: Pipeline, **kwargs, &block)
      end
    end
  end
end
