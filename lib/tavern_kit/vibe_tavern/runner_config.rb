# frozen_string_literal: true

require_relative "capabilities"
require_relative "directives/config"
require_relative "language_policy"
require_relative "output_tags"
require_relative "tool_calling/config"

module TavernKit
  module VibeTavern
    RunnerConfig =
      Data.define(
        :provider,
        :model,
        :runtime,
        :pipeline,
        :llm_options_defaults,
        :capabilities,
        :tool_calling,
        :directives,
        :language_policy,
        :output_tags,
      ) do
        RESERVED_LLM_OPTIONS_KEYS = %i[model messages tools tool_choice response_format stream stream_options].freeze

        def self.build(
          provider:,
          model:,
          runtime: nil,
          pipeline: TavernKit::VibeTavern::Pipeline,
          middleware_options: nil,
          llm_options_defaults: nil
        )
          caps = TavernKit::VibeTavern::Capabilities.resolve(provider: provider, model: model)
          normalized_runtime = normalize_runtime(runtime)
          defaults = normalize_llm_options_defaults(llm_options_defaults)

          tool_calling =
            TavernKit::VibeTavern::ToolCalling::Config.from_runtime(
              normalized_runtime,
              provider: caps.provider,
              model: caps.model,
            )

          directives =
            TavernKit::VibeTavern::Directives::Config.from_runtime(
              normalized_runtime,
              provider: caps.provider,
              model: caps.model,
            )

          language_policy =
            TavernKit::VibeTavern::LanguagePolicy::Config.from_runtime(
              normalized_runtime,
            )

          output_tags =
            TavernKit::VibeTavern::OutputTags::Config.from_runtime(
              normalized_runtime,
            )

          configured_pipeline =
            configure_pipeline(
              pipeline,
              middleware_options: middleware_options,
              language_policy_config: language_policy,
            )

          new(
            provider: caps.provider,
            model: caps.model,
            runtime: normalized_runtime,
            pipeline: configured_pipeline,
            llm_options_defaults: defaults,
            capabilities: caps,
            tool_calling: tool_calling,
            directives: directives,
            language_policy: language_policy,
            output_tags: output_tags,
          )
        end

        def self.normalize_runtime(value)
          return nil if value.nil?
          return value if value.is_a?(TavernKit::Runtime::Base)

          raise ArgumentError, "runtime must be a Hash or TavernKit::Runtime::Base" unless value.is_a?(Hash)

          value.each_key do |key|
            raise ArgumentError, "runtime keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
          end

          TavernKit::Runtime::Base.new(value, type: :vibe_tavern)
        end
        private_class_method :normalize_runtime

        def self.configure_pipeline(pipeline, middleware_options:, language_policy_config:)
          raise ArgumentError, "pipeline is required" if pipeline.nil?
          raise ArgumentError, "pipeline must be a TavernKit::Prompt::Pipeline" unless pipeline.is_a?(TavernKit::Prompt::Pipeline)

          opts = normalize_middleware_options(middleware_options)
          language_policy_options = opts.fetch(:language_policy, {}).dup
          language_policy_options[:config] = language_policy_config
          opts[:language_policy] = language_policy_options

          p = pipeline.dup
          opts.each do |stage, options|
            p.configure(stage, **options)
          end
          p
        end
        private_class_method :configure_pipeline

        def self.normalize_middleware_options(value)
          return {} if value.nil?
          raise ArgumentError, "middleware_options must be a Hash" unless value.is_a?(Hash)

          value.each_with_object({}) do |(name, options), out|
            stage = name.to_s.strip.downcase.tr("-", "_").to_sym
            raise ArgumentError, "middleware_options.#{name} must be a Hash" unless options.is_a?(Hash)

            options.each_key do |key|
              unless key.is_a?(Symbol)
                raise ArgumentError, "middleware_options.#{name} keys must be Symbols (got #{key.class})"
              end
            end

            out[stage] = options.dup
          end
        end
        private_class_method :normalize_middleware_options

        def self.normalize_llm_options_defaults(value)
          h = value.nil? ? {} : value
          raise ArgumentError, "llm_options_defaults must be a Hash" unless h.is_a?(Hash)

          h.each_key do |key|
            raise ArgumentError, "llm_options_defaults keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
          end

          invalid = h.keys & RESERVED_LLM_OPTIONS_KEYS
          raise ArgumentError, "llm_options_defaults contains reserved keys: #{invalid.inspect}" if invalid.any?

          h
        end
        private_class_method :normalize_llm_options_defaults
      end
  end
end
