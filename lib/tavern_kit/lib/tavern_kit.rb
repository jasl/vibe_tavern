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
require_relative "tavern_kit/png/parser"
require_relative "tavern_kit/png/writer"

require_relative "tavern_kit/prompt/message"
require_relative "tavern_kit/prompt/block"
require_relative "tavern_kit/prompt/prompt_entry"
require_relative "tavern_kit/prompt/plan"
require_relative "tavern_kit/prompt/context"
require_relative "tavern_kit/prompt/middleware/base"
require_relative "tavern_kit/prompt/pipeline"
require_relative "tavern_kit/prompt/dsl"

module TavernKit
  class << self
    # Load a character from any supported source.
    # @param input [String, Hash] file path, JSON string, or Hash
    # @return [Character]
    def load_character(input)
      CharacterCard.load(input)
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
