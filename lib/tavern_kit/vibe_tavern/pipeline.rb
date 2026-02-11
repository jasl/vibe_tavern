# frozen_string_literal: true

require_relative "../vibe_tavern"
require_relative "prompt_builder/steps/prepare"
require_relative "prompt_builder/steps/plan_assembly"
require_relative "prompt_builder/steps/language_policy"
require_relative "output_tags/registration"
require_relative "infrastructure"

module TavernKit
  module VibeTavern
    class << self
      def build(**kwargs, &block)
        TavernKit::PromptBuilder.build(pipeline: Pipeline, **kwargs, &block)
      end

      def to_messages(dialect: :openai, **kwargs, &block)
        TavernKit.to_messages(dialect: dialect, pipeline: Pipeline, **kwargs, &block)
      end
    end

    # Default VibeTavern prompt-builder step chain (minimal).
    Pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :prepare, TavernKit::VibeTavern::PromptBuilder::Steps::Prepare
      use_step :plan_assembly, TavernKit::VibeTavern::PromptBuilder::Steps::PlanAssembly
      use_step :language_policy, TavernKit::VibeTavern::PromptBuilder::Steps::LanguagePolicy
      use_step :max_tokens, TavernKit::PromptBuilder::Steps::MaxTokens
    end

    TavernKit.run_load_hooks(:vibe_tavern, TavernKit::VibeTavern.infrastructure)
  end
end
