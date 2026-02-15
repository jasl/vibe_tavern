# frozen_string_literal: true

require_relative "../language_policy_prompt"
require_relative "../openai"
require_relative "detector"

module AgentCore
  module Contrib
    module LanguagePolicy
      module FinalRewriter
        DEFAULT_MAX_INPUT_BYTES = 200_000

        module_function

        def rewrite(
          provider:,
          model:,
          text:,
          llm_options: {},
          target_lang:,
          style_hint: nil,
          special_tags: [],
          token_counter: nil,
          context_window: nil,
          reserved_output_tokens: 0
        )
          lang = AgentCore::Contrib::LanguagePolicy::Detector.canonical_target_lang(target_lang)
          raise ArgumentError, "target_lang is required" if lang.empty?

          input = text.to_s
          return input if input.bytesize > DEFAULT_MAX_INPUT_BYTES
          if AgentCore::Contrib::LanguagePolicy::Detector.language_shape(input, target_lang: lang) == :ok
            return input
          end

          system_text =
            [
              AgentCore::Contrib::LanguagePolicyPrompt.build(
                lang,
                style_hint: style_hint,
                special_tags: special_tags,
                tool_calls_rule: false,
              ),
              "Rewrite the user's text into #{lang}. Output the rewritten text only.",
            ].join("\n\n")

          options = normalize_llm_options(llm_options)
          options[:temperature] = 0 unless options.key?(:temperature)

          prompt =
            AgentCore::PromptBuilder::BuiltPrompt.new(
              system_prompt: system_text,
              messages: [AgentCore::Message.new(role: :user, content: input)],
              tools: [],
              options: { model: model.to_s }.merge(options),
            )

          run_result =
            AgentCore::PromptRunner::Runner.new.run(
              prompt: prompt,
              provider: provider,
              max_turns: 1,
              fix_empty_final: false,
              token_counter: token_counter,
              context_window: context_window,
              reserved_output_tokens: reserved_output_tokens,
            )

          run_result.final_message&.text.to_s
        end

        def normalize_llm_options(value)
          h = value.nil? ? {} : value
          raise ArgumentError, "llm_options must be a Hash" unless h.is_a?(Hash)

          normalized = AgentCore::Utils.deep_symbolize_keys(h)
          AgentCore::Utils.assert_symbol_keys!(normalized, path: "llm_options")

          reserved = normalized.keys & AgentCore::Contrib::OpenAI::RESERVED_CHAT_COMPLETIONS_KEYS
          if reserved.any?
            raise ArgumentError, "llm_options contains reserved keys: #{reserved.map(&:to_s).sort.inspect}"
          end

          normalized
        end
        private_class_method :normalize_llm_options
      end
    end
  end
end
