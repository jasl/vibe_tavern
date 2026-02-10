# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module Directives
      # Small helpers to build directives runner settings.
      #
      # "Presets" are intentionally optional sugar: the source of truth is the
      # config hash itself so upper layers (scripts/app) can compose settings
      # without hidden behavior.
      module Presets
        DEFAULT_MODES = %i[json_schema json_object prompt_only].freeze
        DEFAULT_REPAIR_RETRY_COUNT = 1

        module_function

        def default_directives
          directives(
            modes: DEFAULT_MODES,
            repair_retry_count: DEFAULT_REPAIR_RETRY_COUNT,
          )
        end

        def directives(
          modes: nil,
          repair_retry_count: nil,
          request_overrides: nil,
          structured_request_overrides: nil,
          prompt_only_request_overrides: nil,
          message_transforms: nil,
          response_transforms: nil
        )
          h = {}
          h[:modes] = Array(modes).compact if modes
          h[:repair_retry_count] = repair_retry_count unless repair_retry_count.nil?
          h[:request_overrides] = TavernKit::Utils.normalize_request_overrides(request_overrides) unless request_overrides.nil?
          h[:structured_request_overrides] = TavernKit::Utils.normalize_symbol_keyed_hash(structured_request_overrides, path: "structured_request_overrides") unless structured_request_overrides.nil?
          h[:prompt_only_request_overrides] = TavernKit::Utils.normalize_symbol_keyed_hash(prompt_only_request_overrides, path: "prompt_only_request_overrides") unless prompt_only_request_overrides.nil?
          h[:message_transforms] = Array(message_transforms).compact unless message_transforms.nil?
          h[:response_transforms] = Array(response_transforms).compact unless response_transforms.nil?
          h
        end

        # Optional, opinionated provider defaults for OpenAI-compatible APIs.
        #
        # These are deliberately conservative. Any provider/model-specific hacks
        # must remain opt-in via presets so we don't accidentally send
        # non-standard fields to strict providers.
        def provider_defaults(provider, require_parameters: true)
          case provider.to_s.strip.downcase.tr("-", "_")
          when "openrouter"
            return {} unless require_parameters == true

            directives(
              structured_request_overrides: { provider: { require_parameters: true } },
              prompt_only_request_overrides: { provider: { require_parameters: false } },
            )
          else
            {}
          end
        end

        def for(provider:, model: nil, **kwargs)
          merge(
            default_directives,
            provider_defaults(provider, **kwargs),
            model_defaults(model),
          )
        end

        def model_defaults(_model)
          {}
        end

        # Merge multiple directives config hashes into one.
        #
        # Semantics:
        # - request_overrides: deep-merged (Hash only)
        # - structured_request_overrides/prompt_only_request_overrides: deep-merged (Hash only)
        # - message_transforms/response_transforms: merged as unique string lists
        # - everything else: last write wins
        def merge(*configs)
          Array(configs).compact.reduce({}) do |acc, cfg|
            deep_merge_directives(acc, cfg.is_a?(Hash) ? cfg : {})
          end
        end

        def deep_merge_directives(left, right)
          out = (left.is_a?(Hash) ? left : {}).dup

          (right.is_a?(Hash) ? right : {}).each do |k, v|
            raise ArgumentError, "directives config keys must be Symbols (got #{k.class})" unless k.is_a?(Symbol)
            key = k

            case key
            when :request_overrides, :structured_request_overrides, :prompt_only_request_overrides
              merged =
                TavernKit::Utils.deep_merge_hashes(
                  TavernKit::Utils.normalize_symbol_keyed_hash(out[key], path: key),
                  TavernKit::Utils.normalize_symbol_keyed_hash(v, path: key),
                )
              out[key] = merged
            when :message_transforms, :response_transforms
              out[key] = TavernKit::Utils.merge_string_list(out[key], v)
            else
              out[key] = v
            end
          end

          out
        end
        private_class_method :deep_merge_directives
      end
    end
  end
end
