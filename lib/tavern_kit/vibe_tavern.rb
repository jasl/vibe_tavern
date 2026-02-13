# frozen_string_literal: true

require_relative "vibe_tavern/capabilities"
require_relative "vibe_tavern/directives"
require_relative "vibe_tavern/infrastructure"
require_relative "vibe_tavern/json_schema"
require_relative "vibe_tavern/language_policy"
require_relative "vibe_tavern/liquid_macros"
require_relative "vibe_tavern/output_tags"
require_relative "vibe_tavern/preflight"
require_relative "vibe_tavern/transforms"
require_relative "vibe_tavern/prompt_runner"
require_relative "vibe_tavern/result"
require_relative "vibe_tavern/request_policy"
require_relative "vibe_tavern/runner_config"
require_relative "vibe_tavern/token_estimation"
require_relative "vibe_tavern/tool_calling"
require_relative "vibe_tavern/tools"
require_relative "vibe_tavern/tools_builder"
require_relative "vibe_tavern/user_input_preprocessor"
require_relative "vibe_tavern/generation"
require_relative "vibe_tavern/pipeline"

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
