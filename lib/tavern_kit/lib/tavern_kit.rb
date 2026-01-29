# frozen_string_literal: true

require "json"

require_relative "tavern_kit/version"

require_relative "tavern_kit/constants"
require_relative "tavern_kit/coerce"
require_relative "tavern_kit/errors"
require_relative "tavern_kit/utils"

require_relative "tavern_kit/participant"
require_relative "tavern_kit/user"

require_relative "tavern_kit/character"
require_relative "tavern_kit/character_card"
require_relative "tavern_kit/character_importer"
require_relative "tavern_kit/png/parser"
require_relative "tavern_kit/png/writer"

require_relative "tavern_kit/chat_history"
require_relative "tavern_kit/chat_history/in_memory"
require_relative "tavern_kit/chat_variables"
require_relative "tavern_kit/chat_variables/in_memory"
require_relative "tavern_kit/token_estimator"
require_relative "tavern_kit/trim_report"

require_relative "tavern_kit/preset/base"

require_relative "tavern_kit/macro/engine/base"
require_relative "tavern_kit/macro/environment/base"
require_relative "tavern_kit/macro/registry/base"

require_relative "tavern_kit/lore/scan_input"
require_relative "tavern_kit/lore/entry"
require_relative "tavern_kit/lore/book"
require_relative "tavern_kit/lore/result"
require_relative "tavern_kit/lore/engine/base"

require_relative "tavern_kit/hook_registry/base"
require_relative "tavern_kit/injection_registry/base"

require_relative "tavern_kit/prompt/message"
require_relative "tavern_kit/prompt/block"
require_relative "tavern_kit/prompt/prompt_entry"
require_relative "tavern_kit/prompt/plan"
require_relative "tavern_kit/prompt/context"
require_relative "tavern_kit/prompt/trace"
require_relative "tavern_kit/prompt/instrumenter"
require_relative "tavern_kit/prompt/middleware/base"
require_relative "tavern_kit/prompt/pipeline"
require_relative "tavern_kit/prompt/dsl"

require_relative "tavern_kit/silly_tavern/context_template"
require_relative "tavern_kit/silly_tavern/instruct"
require_relative "tavern_kit/silly_tavern/preset"

module TavernKit
  class << self
    # Load a character from any supported source.
    # @param input [String, Hash] file path, JSON string, or Hash
    # @return [Character]
    def load_character(input)
      CharacterImporter.load(input)
    end

    # Build a prompt using the DSL-based pipeline.
    #
    # Requires explicit pipeline selection — there is no default.
    #
    # @example Block style
    #   plan = TavernKit.build(pipeline: TavernKit::SillyTavern::Pipeline) do
    #     character my_char
    #     user my_user
    #     message "Hello!"
    #   end
    #
    # @param pipeline [Prompt::Pipeline] the pipeline to use (required)
    # @yield [Prompt::DSL] DSL configuration block
    # @return [Prompt::Plan]
    def build(pipeline:, **kwargs, &block)
      if block
        Prompt::DSL.build(pipeline: pipeline, &block)
      else
        dsl = Prompt::DSL.new(pipeline: pipeline)
        kwargs.each do |key, value|
          dsl.public_send(key, value) if dsl.respond_to?(key)
        end
        dsl.build
      end
    end

    # Build messages directly using the pipeline.
    #
    # @param dialect [Symbol] output dialect (:openai, :anthropic, etc.)
    # @param pipeline [Prompt::Pipeline] the pipeline to use (required)
    # @return [Array<Hash>]
    def to_messages(dialect: :openai, pipeline:, **kwargs, &block)
      plan = build(pipeline: pipeline, **kwargs, &block)
      plan.to_messages(dialect: dialect)
    end
  end
end
