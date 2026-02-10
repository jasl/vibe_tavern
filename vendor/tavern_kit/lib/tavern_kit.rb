# frozen_string_literal: true

require "json"

require_relative "tavern_kit/version"

require_relative "tavern_kit/constants"
require_relative "tavern_kit/coerce"
require_relative "tavern_kit/errors"
require_relative "tavern_kit/utils"
require_relative "tavern_kit/regex_safety"
require_relative "tavern_kit/text/language_tag"
require_relative "tavern_kit/text/json_pointer"
require_relative "tavern_kit/text/verbatim_masker"
require_relative "tavern_kit/lru_cache"
require_relative "tavern_kit/js_regex_cache"
require_relative "tavern_kit/load_hooks"

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
require_relative "tavern_kit/variables_store"
require_relative "tavern_kit/variables_store/in_memory"
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

require_relative "tavern_kit/prompt_builder"
require_relative "tavern_kit/prompt_builder/message"
require_relative "tavern_kit/prompt_builder/block"
require_relative "tavern_kit/prompt_builder/prompt_entry"
require_relative "tavern_kit/prompt_builder/plan"
require_relative "tavern_kit/prompt_inspector"
require_relative "tavern_kit/prompt_builder/context"
require_relative "tavern_kit/prompt_builder/state"
require_relative "tavern_kit/prompt_builder/trace"
require_relative "tavern_kit/prompt_builder/instrumenter"
require_relative "tavern_kit/prompt_builder/step"
require_relative "tavern_kit/prompt_builder/steps/max_tokens"
require_relative "tavern_kit/prompt_builder/pipeline"
require_relative "tavern_kit/prompt_builder/dialects/base"
require_relative "tavern_kit/prompt_builder/dialects/openai"
require_relative "tavern_kit/prompt_builder/dialects/anthropic"
require_relative "tavern_kit/prompt_builder/dialects/google"
require_relative "tavern_kit/prompt_builder/dialects/cohere"
require_relative "tavern_kit/prompt_builder/dialects/ai21"
require_relative "tavern_kit/prompt_builder/dialects/mistral"
require_relative "tavern_kit/prompt_builder/dialects/xai"
require_relative "tavern_kit/prompt_builder/dialects/text"

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
    def on_load(scope, id: nil, &block)
      LoadHooks.on_load(scope, id: id, &block)
    end

    def run_load_hooks(scope, payload)
      LoadHooks.run_load_hooks(scope, payload)
    end

    # Parse a character from a Hash (e.g. JSON.parse result).
    #
    # For file-based formats (png/byaf/charx), use TavernKit::Ingest.
    #
    # @param hash [Hash]
    # @return [Character]
    def load_character(hash)
      CharacterCard.load(hash)
    end

    # Build a prompt using PromptBuilder.
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
    # @param pipeline [PromptBuilder::Pipeline] the pipeline to use (required)
    # @return [PromptBuilder::Plan]
    def build(pipeline:, **kwargs, &block)
      if block
        PromptBuilder.build(pipeline: pipeline, **kwargs, &block)
      else
        PromptBuilder.build(pipeline: pipeline, **kwargs)
      end
    end

    # Build messages directly using the pipeline.
    #
    # @param dialect [Symbol] output dialect (:openai, :anthropic, etc.)
    # @param pipeline [PromptBuilder::Pipeline] the pipeline to use (required)
    # @return [Array<Hash>]
    def to_messages(dialect: :openai, pipeline:, **kwargs, &block)
      if block
        PromptBuilder.to_messages(dialect: dialect, pipeline: pipeline, **kwargs, &block)
      else
        PromptBuilder.to_messages(dialect: dialect, pipeline: pipeline, **kwargs)
      end
    end
  end
end
