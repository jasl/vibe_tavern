# frozen_string_literal: true

require "json"

require_relative "tavern_kit/version"

require_relative "tavern_kit/constants"
require_relative "tavern_kit/coerce"
require_relative "tavern_kit/errors"
require_relative "tavern_kit/utils"
require_relative "tavern_kit/lru_cache"
require_relative "tavern_kit/js_regex_cache"
require_relative "tavern_kit/runtime"

require_relative "tavern_kit/participant"
require_relative "tavern_kit/user"

require_relative "tavern_kit/character"
require_relative "tavern_kit/character_card"
require_relative "tavern_kit/png/parser"
require_relative "tavern_kit/png/writer"
require_relative "tavern_kit/archive/zip_reader"
require_relative "tavern_kit/archive/byaf"
require_relative "tavern_kit/archive/charx"
require_relative "tavern_kit/ingest"

require_relative "tavern_kit/chat_history"
require_relative "tavern_kit/chat_history/in_memory"
require_relative "tavern_kit/chat_variables"
require_relative "tavern_kit/chat_variables/in_memory"
require_relative "tavern_kit/token_estimator"
require_relative "tavern_kit/trim_report"
require_relative "tavern_kit/trimmer"

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
require_relative "tavern_kit/injection_registry/entry"

require_relative "tavern_kit/prompt/message"
require_relative "tavern_kit/prompt/block"
require_relative "tavern_kit/prompt/prompt_entry"
require_relative "tavern_kit/prompt/plan"
require_relative "tavern_kit/prompt/context"
require_relative "tavern_kit/prompt/trace"
require_relative "tavern_kit/prompt/instrumenter"
require_relative "tavern_kit/prompt/middleware/base"
require_relative "tavern_kit/prompt/middleware/max_tokens"
require_relative "tavern_kit/prompt/pipeline"
require_relative "tavern_kit/prompt/dsl"
require_relative "tavern_kit/prompt/dialects/base"
require_relative "tavern_kit/prompt/dialects/openai"
require_relative "tavern_kit/prompt/dialects/anthropic"
require_relative "tavern_kit/prompt/dialects/google"
require_relative "tavern_kit/prompt/dialects/cohere"
require_relative "tavern_kit/prompt/dialects/ai21"
require_relative "tavern_kit/prompt/dialects/mistral"
require_relative "tavern_kit/prompt/dialects/xai"
require_relative "tavern_kit/prompt/dialects/text"

require_relative "tavern_kit/silly_tavern/context_template"
require_relative "tavern_kit/silly_tavern/examples_parser"
require_relative "tavern_kit/silly_tavern/expander_vars"
require_relative "tavern_kit/silly_tavern/group_context"
require_relative "tavern_kit/silly_tavern/in_chat_injector"
require_relative "tavern_kit/silly_tavern/injection_planner"
require_relative "tavern_kit/silly_tavern/instruct"
require_relative "tavern_kit/silly_tavern/hook_registry"
require_relative "tavern_kit/silly_tavern/injection_registry"
require_relative "tavern_kit/silly_tavern/preset"
require_relative "tavern_kit/silly_tavern/macro/environment"
require_relative "tavern_kit/silly_tavern/macro/flags"
require_relative "tavern_kit/silly_tavern/macro/invocation"
require_relative "tavern_kit/silly_tavern/macro/preprocessors"
require_relative "tavern_kit/silly_tavern/macro/registry"
require_relative "tavern_kit/silly_tavern/macro/packs/silly_tavern"
require_relative "tavern_kit/silly_tavern/macro/v1_engine"
require_relative "tavern_kit/silly_tavern/macro/v2_engine"
require_relative "tavern_kit/silly_tavern/lore/entry_extensions"
require_relative "tavern_kit/silly_tavern/lore/key_list"
require_relative "tavern_kit/silly_tavern/lore/decorator_parser"
require_relative "tavern_kit/silly_tavern/lore/engine"
require_relative "tavern_kit/silly_tavern/lore/scan_input"
require_relative "tavern_kit/silly_tavern/lore/timed_effects"
require_relative "tavern_kit/silly_tavern/lore/world_info_importer"
require_relative "tavern_kit/silly_tavern/build"

require_relative "tavern_kit/risu_ai"

module TavernKit
  class << self
    # Parse a character from a Hash (e.g. JSON.parse result).
    #
    # For file-based formats (png/byaf/charx), use TavernKit::Ingest.
    #
    # @param hash [Hash]
    # @return [Character]
    def load_character(hash)
      CharacterCard.load(hash)
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
      dsl = Prompt::DSL.new(pipeline: pipeline)
      dsl.dialect(dialect)

      if block
        dsl.instance_eval(&block)
      else
        kwargs.each do |key, value|
          dsl.public_send(key, value) if dsl.respond_to?(key)
        end
      end

      dsl.to_messages(dialect: dialect)
    end
  end
end
