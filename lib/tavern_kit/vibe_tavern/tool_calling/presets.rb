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

        # Canonical default settings for tool calling in the rewrite.
        #
        # This is intentionally explicit so upper layers can:
        # - start from a known baseline
        # - merge additional provider/model-specific presets on top
        #
        # @return [Hash] a hash suitable for `runtime[:tool_calling]`
        def default_tool_calling
          tool_calling(
            tool_use_mode: :relaxed,
            fix_empty_final: true,
            fix_empty_final_disable_tools: true,
            response_transforms: [
              "assistant_function_call_to_tool_calls",
              "assistant_tool_calls_object_to_array",
              "assistant_tool_calls_arguments_json_string_if_hash",
            ],
            tool_call_transforms: ["assistant_tool_calls_arguments_blank_to_empty_object"],
            fallback_retry_count: 0,
          )
        end

        # Generic tool-calling runtime configuration.
        #
        # @return [Hash] a hash suitable for `runtime[:tool_calling]`
        def tool_calling(
          tool_use_mode: :enforced,
          tool_failure_policy: nil,
          tool_allowlist: nil,
          tool_denylist: nil,
          fix_empty_final: true,
          fix_empty_final_user_text: nil,
          fix_empty_final_disable_tools: nil,
          message_transforms: nil,
          tool_transforms: nil,
          response_transforms: nil,
          tool_call_transforms: nil,
          tool_result_transforms: nil,
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

          h[:tool_failure_policy] = tool_failure_policy unless tool_failure_policy.nil?
          h[:tool_allowlist] = tool_allowlist unless tool_allowlist.nil?
          h[:tool_denylist] = tool_denylist unless tool_denylist.nil?
          h[:tool_choice] = tool_choice unless tool_choice.nil?
          h[:max_tool_args_bytes] = max_tool_args_bytes unless max_tool_args_bytes.nil?
          h[:max_tool_output_bytes] = max_tool_output_bytes unless max_tool_output_bytes.nil?
          h[:fix_empty_final_user_text] = fix_empty_final_user_text unless fix_empty_final_user_text.nil?
          h[:fix_empty_final_disable_tools] = fix_empty_final_disable_tools unless fix_empty_final_disable_tools.nil?
          h[:message_transforms] = message_transforms unless message_transforms.nil?
          h[:tool_transforms] = tool_transforms unless tool_transforms.nil?
          h[:response_transforms] = response_transforms unless response_transforms.nil?
          h[:tool_call_transforms] = tool_call_transforms unless tool_call_transforms.nil?
          h[:tool_result_transforms] = tool_result_transforms unless tool_result_transforms.nil?
          h[:request_overrides] = normalize_request_overrides(request_overrides) unless request_overrides.nil?

          h
        end

        # Wrap a request overrides hash into a `runtime[:tool_calling]` shape.
        #
        # @return [Hash] a hash suitable for `runtime[:tool_calling]`
        def request_overrides(overrides)
          { request_overrides: normalize_request_overrides(overrides) }
        end

        def message_transforms(*names)
          { message_transforms: names.flatten.compact }
        end

        def tool_transforms(*names)
          { tool_transforms: names.flatten.compact }
        end

        def response_transforms(*names)
          { response_transforms: names.flatten.compact }
        end

        def tool_call_transforms(*names)
          { tool_call_transforms: names.flatten.compact }
        end

        def tool_result_transforms(*names)
          { tool_result_transforms: names.flatten.compact }
        end

        # Optional, opinionated provider defaults for OpenAI-compatible APIs.
        #
        # These are deliberately conservative. Any provider/model-specific hacks
        # must remain opt-in via presets so we don't accidentally send
        # non-standard fields to strict providers.
        #
        # @return [Hash] a hash suitable for `runtime[:tool_calling]`
        def provider_defaults(provider, **kwargs)
          case provider.to_s.strip.downcase.tr("-", "_")
          when "openrouter"
            merge(
              openai_compatible_reliability(parallel_tool_calls: false),
              openrouter_tool_calling(**kwargs),
            )
          when "openai"
            openai_compatible_reliability
          when "volcanoengine", "volcano_engine", "volcano"
            openai_compatible_reliability
          else
            {}
          end
        end

        # Optional, opinionated model defaults.
        #
        # @return [Hash] a hash suitable for `runtime[:tool_calling]`
        def model_defaults(model)
          m = model.to_s.strip
          return {} if m.empty?

          presets = []

          # Known: does not support tool use in our eval harness.
          presets << tool_calling(tool_use_mode: :disabled) if m == "minimax/minimax-m2-her"

          # Some OpenAI-compatible routes/models require a dummy reasoning field
          # on assistant messages that contain tool calls.
          presets << deepseek_openrouter_compat if m.start_with?("deepseek/")

          # Gemini routes can be stricter around function-call tracing.
          presets << gemini_openrouter_compat if m.start_with?("google/gemini-")

          # Keep compatibility with generic "reasoner" model names.
          presets << tool_calling(message_transforms: ["assistant_tool_calls_reasoning_content_empty_if_missing"]) if m.downcase.include?("reasoner")

          merge(*presets)
        end

        # Convenience helper to build a baseline tool-calling config for a given
        # OpenAI-compatible provider/model combination.
        #
        # @return [Hash] a hash suitable for `runtime[:tool_calling]`
        def for(provider:, model: nil, **kwargs)
          merge(
            default_tool_calling,
            provider_defaults(provider, **kwargs),
            model_defaults(model),
          )
        end

        # Merge multiple `runtime[:tool_calling]` hashes into one.
        #
        # Semantics:
        # - request_overrides: deep-merged (Hash only)
        # - tool_allowlist/tool_denylist and *_transforms: merged as unique string lists
        # - everything else: last write wins
        #
        # @return [Hash] a merged hash suitable for `runtime[:tool_calling]`
        def merge(*configs)
          Array(configs).compact.reduce({}) do |acc, cfg|
            deep_merge_tool_calling(acc, cfg.is_a?(Hash) ? cfg : {})
          end
        end

        def openrouter_tool_calling(route: nil, transforms: nil, provider_only: nil, provider_order: nil, provider_ignore: nil, request_overrides: nil)
          merged_overrides =
            deep_merge_hashes(
              normalize_request_overrides(
                openrouter_routing(
                  route: route,
                  transforms: transforms,
                  provider_only: provider_only,
                  provider_order: provider_order,
                  provider_ignore: provider_ignore,
                ),
              ),
              normalize_request_overrides(request_overrides),
            )

          tool_calling(
            request_overrides: merged_overrides,
          )
        end

        # Conservative reliability helpers for OpenAI-compatible tool calling.
        #
        # - Keep argument normalization in both inbound response and parsed tool calls
        # - Optionally force sequential tool calls (`parallel_tool_calls: false`)
        # - Keep optional text-tag fallback disabled unless explicitly requested
        #
        # @return [Hash] a hash suitable for `runtime[:tool_calling]`
        def openai_compatible_reliability(parallel_tool_calls: nil, enable_content_tag_fallback: false)
          response_transforms = [
            "assistant_function_call_to_tool_calls",
            "assistant_tool_calls_object_to_array",
            "assistant_tool_calls_arguments_json_string_if_hash",
          ]

          if enable_content_tag_fallback
            response_transforms += ["assistant_content_tool_call_tags_to_tool_calls"]
          end

          cfg =
            tool_calling(
              response_transforms: response_transforms,
              tool_call_transforms: ["assistant_tool_calls_arguments_blank_to_empty_object"],
            )

          return cfg if parallel_tool_calls.nil?

          merge(
            cfg,
            request_overrides(parallel_tool_calls: parallel_tool_calls),
          )
        end

        # Optional fallback for weaker models/routes that emit textual
        # `<tool_call>...</tool_call>` tags instead of structured tool_calls.
        #
        # Keep this opt-in to avoid affecting normal OpenAI-compatible paths.
        #
        # @return [Hash] a hash suitable for `runtime[:tool_calling]`
        def content_tag_tool_call_fallback
          tool_calling(
            response_transforms: ["assistant_content_tool_call_tags_to_tool_calls"],
          )
        end

        # DeepSeek-compatible compatibility defaults observed in practice.
        #
        # @return [Hash] a hash suitable for `runtime[:tool_calling]`
        def deepseek_openrouter_compat
          tool_calling(
            message_transforms: ["assistant_tool_calls_reasoning_content_empty_if_missing"],
          )
        end

        # Gemini-compatible compatibility defaults observed in practice.
        #
        # @return [Hash] a hash suitable for `runtime[:tool_calling]`
        def gemini_openrouter_compat
          tool_calling(
            message_transforms: ["assistant_tool_calls_signature_skip_validator_if_missing"],
          )
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
          only = normalize_string_list(provider_only) if provider_only
          order = normalize_string_list(provider_order) if provider_order
          ignore = normalize_string_list(provider_ignore) if provider_ignore

          provider[:only] = only if only
          provider[:order] = order if order
          provider[:ignore] = ignore if ignore
          overrides[:provider] = provider if provider.any?

          overrides
        end

        def normalize_string_list(value)
          list = Array(value).map { |v| v.to_s.strip }.reject(&:empty?)
          list.empty? ? nil : list
        end
        private_class_method :normalize_string_list

        def deep_merge_tool_calling(left, right)
          out = (left.is_a?(Hash) ? left : {}).dup

          (right.is_a?(Hash) ? right : {}).each do |k, v|
            key = canonical_tool_calling_key(k)

            case key
            when :request_overrides
              merged =
                deep_merge_hashes(
                  normalize_request_overrides(out[:request_overrides]),
                  normalize_request_overrides(v),
                )
              out[:request_overrides] = merged
            when :tool_allowlist, :tool_denylist, :message_transforms, :tool_transforms, :response_transforms, :tool_call_transforms, :tool_result_transforms
              out[key] = merge_string_list(out[key], v)
            else
              out[key] = v
            end
          end

          out
        end
        private_class_method :deep_merge_tool_calling

        def canonical_tool_calling_key(key)
          key.to_s.to_sym
        end
        private_class_method :canonical_tool_calling_key

        def merge_string_list(left, right)
          return nil if right.nil?

          right_list = normalize_string_list(right)
          return [] if explicit_empty_string_list?(right)

          left_list = normalize_string_list(left)
          return right_list if left_list.nil?

          (left_list + right_list).uniq
        end
        private_class_method :merge_string_list

        def explicit_empty_string_list?(value)
          case value
          when String
            value.split(",").map(&:strip).reject(&:empty?).empty?
          when Array
            value.map { |v| v.to_s.strip }.reject(&:empty?).empty?
          else
            false
          end
        end
        private_class_method :explicit_empty_string_list?

        def normalize_request_overrides(value)
          return {} if value.nil?
          return deep_symbolize_keys(value) if value.is_a?(Hash)

          {}
        end
        private_class_method :normalize_request_overrides

        def deep_symbolize_keys(value)
          case value
          when Hash
            value.each_with_object({}) do |(k, v), out|
              if k.is_a?(Symbol)
                out[k] = deep_symbolize_keys(v)
              else
                sym = k.to_s.to_sym
                out[sym] = deep_symbolize_keys(v) unless out.key?(sym)
              end
            end
          when Array
            value.map { |v| deep_symbolize_keys(v) }
          else
            value
          end
        end
        private_class_method :deep_symbolize_keys

        def deep_merge_hashes(left, right)
          out = (left.is_a?(Hash) ? left : {}).dup
          (right.is_a?(Hash) ? right : {}).each do |k, v|
            if out[k].is_a?(Hash) && v.is_a?(Hash)
              out[k] = deep_merge_hashes(out[k], v)
            else
              out[k] = v
            end
          end
          out
        end
        private_class_method :deep_merge_hashes
      end
    end
  end
end
