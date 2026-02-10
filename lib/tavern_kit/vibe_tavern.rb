# frozen_string_literal: true

module TavernKit
  # Application-owned prompt-building pipeline for the Rails rewrite.
  #
  # This lives in the Rails app's `lib/` (autoloaded by Rails) and is intended
  # to evolve independently from the SillyTavern/RisuAI platform pipelines.
  module VibeTavern
    class << self
      # Convenience entrypoint using the default VibeTavern pipeline.
      def build(**kwargs, &block)
        TavernKit::PromptBuilder.build(pipeline: Pipeline, **kwargs, &block)
      end

      def to_messages(dialect: :openai, **kwargs, &block)
        TavernKit.to_messages(dialect: dialect, pipeline: Pipeline, **kwargs, &block)
      end
    end
  end
end
