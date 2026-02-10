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
        if block
          TavernKit::PromptBuilder.build(pipeline: Pipeline, &block)
        else
          builder = TavernKit::PromptBuilder.new(pipeline: Pipeline)
          kwargs.each do |key, value|
            builder.public_send(key, value) if builder.respond_to?(key)
          end
          builder.build
        end
      end

      def to_messages(dialect: :openai, **kwargs, &block)
        TavernKit.to_messages(dialect: dialect, pipeline: Pipeline, **kwargs, &block)
      end
    end

    # Default VibeTavern prompt-builder step chain (minimal).
    Pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step TavernKit::VibeTavern::PromptBuilder::Steps::Prepare, name: :prepare
      use_step TavernKit::VibeTavern::PromptBuilder::Steps::PlanAssembly, name: :plan_assembly
      use_step TavernKit::VibeTavern::PromptBuilder::Steps::LanguagePolicy, name: :language_policy
    end

    TavernKit.run_load_hooks(:vibe_tavern, TavernKit::VibeTavern.infrastructure)
  end
end
