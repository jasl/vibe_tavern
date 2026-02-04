# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolCalling
      # Small helpers to build `runtime[:tool_calling]` hashes.
      #
      # "Presets" are intentionally optional sugar: the source of truth is the
      # runtime hash itself so upper layers (scripts/app) can compose settings
      # without hidden behavior.
      module Presets
        module_function

        # Generic tool-calling runtime configuration.
        #
        # @return [Hash] a hash suitable for `runtime[:tool_calling]`
        def tool_calling(
          tool_use_mode: :enforced,
          tool_allowlist: nil,
          tool_denylist: nil,
          fix_empty_final: true,
          fallback_retry_count: 0,
          tool_choice: nil,
          max_tool_args_bytes: nil,
          max_tool_output_bytes: nil,
          request_overrides: nil
        )
          h = {
            tool_use_mode: tool_use_mode,
            fix_empty_final: fix_empty_final,
            fallback_retry_count: fallback_retry_count,
          }

          h[:tool_allowlist] = tool_allowlist unless tool_allowlist.nil?
          h[:tool_denylist] = tool_denylist unless tool_denylist.nil?
          h[:tool_choice] = tool_choice unless tool_choice.nil?
          h[:max_tool_args_bytes] = max_tool_args_bytes unless max_tool_args_bytes.nil?
          h[:max_tool_output_bytes] = max_tool_output_bytes unless max_tool_output_bytes.nil?
          h[:request_overrides] = request_overrides unless request_overrides.nil?

          h
        end

        # OpenRouter is OpenAI-compatible but supports extra routing knobs.
        # We keep these as request-level overrides so tool calling stays SRP.
        #
        # @return [Hash] request overrides hash (merge into `request_overrides`)
        def openrouter_routing(route: nil, transforms: nil, provider_only: nil, provider_order: nil, provider_ignore: nil)
          overrides = {}
          overrides[:route] = route.to_s if route && !route.to_s.strip.empty?

          if transforms
            list = Array(transforms).map { |v| v.to_s.strip }.reject(&:empty?)
            overrides[:transforms] = list
          end

          provider = {}
          provider[:only] = normalize_string_list(provider_only) if provider_only
          provider[:order] = normalize_string_list(provider_order) if provider_order
          provider[:ignore] = normalize_string_list(provider_ignore) if provider_ignore
          overrides[:provider] = provider if provider.any?

          overrides
        end

        def normalize_string_list(value)
          list = Array(value).map { |v| v.to_s.strip }.reject(&:empty?)
          list.empty? ? nil : list
        end
        private_class_method :normalize_string_list
      end
    end
  end
end
