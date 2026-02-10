# frozen_string_literal: true

require_relative "pipeline"

module TavernKit
  module RisuAI
    class << self
      # Convenience entrypoint using the default RisuAI pipeline.
      def build(**kwargs, &block)
        if block
          TavernKit::PromptBuilder.build(pipeline: Pipeline, &block)
        else
          dsl = TavernKit::PromptBuilder.new(pipeline: Pipeline)
          kwargs.each do |key, value|
            dsl.public_send(key, value) if dsl.respond_to?(key)
          end
          dsl.build
        end
      end

      def to_messages(dialect: :openai, **kwargs, &block)
        TavernKit.to_messages(dialect: dialect, pipeline: Pipeline, **kwargs, &block)
      end
    end
  end
end
