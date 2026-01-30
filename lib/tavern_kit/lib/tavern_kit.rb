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
require_relative "tavern_kit/silly_tavern/byaf_parser"
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

module TavernKit
  class << self
    # Load a character from any supported source.
    # @param input [String, Hash] file path, JSON string, or Hash
    # @return [Character]
    def load_character(input)
      CharacterImporter.load(input)
    end

    # Load a SillyTavern preset from a file path or Hash.
    #
    # This is a convenience API for downstream apps migrating from the legacy
    # gem where presets were loaded via `TavernKit.load_preset(...)`.
    #
    # @param input [String, Hash, nil] file path, JSON string, or Hash
    # @return [SillyTavern::Preset]
    def load_preset(input)
      return TavernKit::SillyTavern::Preset.new if input.nil?

      if input.is_a?(String)
        str = input.to_s

        if File.exist?(str)
          return TavernKit::SillyTavern::Preset.load_st_preset_file(str)
        end

        trimmed = str.strip
        if trimmed.start_with?("{")
          return load_preset(JSON.parse(trimmed))
        end

        raise ArgumentError, "Preset path does not exist: #{input.inspect}"
      end

      unless input.is_a?(Hash)
        raise ArgumentError, "Preset input must be a Hash or file path, got: #{input.class}"
      end

      h = Utils.deep_stringify_keys(input)

      # Auto-detect ST preset JSON shape (Prompt Manager).
      if h.key?("prompts") || h.key?("prompt_order") || h.key?("promptOrder")
        return TavernKit::SillyTavern::Preset.from_st_preset_json(h)
      end

      allowed = TavernKit::SillyTavern::Preset.members.map(&:to_s)
      kwargs = h.each_with_object({}) do |(k, v), out|
        key = k.to_s
        next unless allowed.include?(key)

        out[key.to_sym] = v
      end

      TavernKit::SillyTavern::Preset.new(**kwargs)
    end

    # Global custom macro registry (legacy gem compatibility).
    #
    # Downstream apps can register additional macros here and they will be
    # consulted before built-in ST macros during expansion.
    #
    # Note: this is intentionally process-global state; prefer per-request
    # `ctx.macro_registry` when you need isolation.
    def macros
      @macros ||= TavernKit::SillyTavern::Macro::Registry.new
    end

    # Returns the default pipeline for this gem (SillyTavern).
    #
    # Kept as a convenience for downstream apps; Wave 4 docs still recommend
    # using `TavernKit::SillyTavern.build` for ST-style prompt building.
    def pipeline
      TavernKit::SillyTavern::Pipeline
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
