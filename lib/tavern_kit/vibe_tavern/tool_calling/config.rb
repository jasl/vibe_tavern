# frozen_string_literal: true

require_relative "constants"
require_relative "presets"

module TavernKit
  module VibeTavern
    module ToolCalling
      Config =
        Data.define(
          :tool_use_mode,
          :tool_failure_policy,
          :tool_allowlist,
          :tool_denylist,
          :policy,
          :policy_error_mode,
          :event_context_keys,
          :fix_empty_final,
          :fix_empty_final_user_text,
          :fix_empty_final_disable_tools,
          :fallback_retry_count,
          :max_tool_definitions_count,
          :max_tool_definitions_bytes,
          :max_tool_args_bytes,
          :max_tool_output_bytes,
          :max_tool_calls_per_turn,
          :tool_choice,
          :message_transforms,
          :tool_transforms,
          :response_transforms,
          :tool_call_transforms,
          :tool_result_transforms,
          :request_overrides,
        ) do
          def tool_use_enabled?
            tool_use_mode != :disabled
          end

          def self.from_context(context, provider:, model: nil)
            base =
              TavernKit::VibeTavern::ToolCalling::Presets.for(
                provider: provider,
                model: model,
              )

            raw = context&.[](:tool_calling)
            raise ArgumentError, "context[:tool_calling] must be a Hash" unless raw.nil? || raw.is_a?(Hash)

            merged =
              TavernKit::VibeTavern::ToolCalling::Presets.merge(
                base,
                raw,
              )

            build_from_hash(merged)
          end

          def self.build_from_hash(raw)
            raise ArgumentError, "tool_calling config must be a Hash" unless raw.is_a?(Hash)
            TavernKit::Utils.assert_symbol_keys!(raw, path: "tool_calling config")

            tool_use_mode = raw.fetch(:tool_use_mode, :relaxed)
            tool_use_mode = tool_use_mode.to_s.strip.downcase.tr("-", "_").to_sym
            raise ArgumentError, "tool_use_mode not supported: #{tool_use_mode.inspect}" unless TOOL_USE_MODES.include?(tool_use_mode)

            tool_failure_policy = raw.fetch(:tool_failure_policy, :tolerated)
            tool_failure_policy = tool_failure_policy.to_s.strip.downcase.tr("-", "_").to_sym
            unless TOOL_FAILURE_POLICIES.include?(tool_failure_policy)
              raise ArgumentError, "tool_failure_policy not supported: #{tool_failure_policy.inspect}"
            end

            fix_empty_final = !!raw.fetch(:fix_empty_final, true)
            fix_empty_final_user_text = raw.fetch(:fix_empty_final_user_text, nil)&.to_s
            fix_empty_final_disable_tools = raw.key?(:fix_empty_final_disable_tools) ? !!raw.fetch(:fix_empty_final_disable_tools) : true

            fallback_retry_count = integer_or_default(raw.fetch(:fallback_retry_count, 0), default: 0)

            max_tool_definitions_count =
              positive_int_or_default(
                raw.fetch(:max_tool_definitions_count, nil),
                default: DEFAULT_MAX_TOOL_DEFINITIONS_COUNT,
              )
            max_tool_definitions_bytes =
              positive_int_or_default(
                raw.fetch(:max_tool_definitions_bytes, nil),
                default: DEFAULT_MAX_TOOL_DEFINITIONS_BYTES,
              )

            max_tool_args_bytes = positive_int_or_default(raw.fetch(:max_tool_args_bytes, nil), default: DEFAULT_MAX_TOOL_ARGS_BYTES)
            max_tool_output_bytes = positive_int_or_default(raw.fetch(:max_tool_output_bytes, nil), default: DEFAULT_MAX_TOOL_OUTPUT_BYTES)
            max_tool_calls_per_turn = positive_int_or_default(raw.fetch(:max_tool_calls_per_turn, nil), default: nil)

            tool_choice = raw.fetch(:tool_choice, nil)
            tool_choice = normalize_tool_choice(tool_choice)

            tool_allowlist = normalize_string_list(raw.fetch(:tool_allowlist, nil))
            tool_denylist = normalize_string_list(raw.fetch(:tool_denylist, nil))

            policy = raw.fetch(:policy, nil)
            unless policy.nil? || (policy.respond_to?(:filter_tools) && policy.respond_to?(:authorize_call))
              raise ArgumentError, "tool_calling.policy must respond to #filter_tools and #authorize_call"
            end

            policy_error_mode = normalize_policy_error_mode(raw.fetch(:policy_error_mode, :deny))
            event_context_keys = normalize_event_context_keys(raw.fetch(:event_context_keys, nil))

            message_transforms = normalize_string_array(raw.fetch(:message_transforms, nil))
            tool_transforms = normalize_string_array(raw.fetch(:tool_transforms, nil))
            response_transforms = normalize_string_array(raw.fetch(:response_transforms, nil))
            tool_call_transforms = normalize_string_array(raw.fetch(:tool_call_transforms, nil))
            tool_result_transforms = normalize_string_array(raw.fetch(:tool_result_transforms, nil))

            request_overrides = TavernKit::Utils.normalize_symbol_keyed_hash(raw.fetch(:request_overrides, {}), path: "tool_calling.request_overrides")

            reserved = %i[model messages tools tool_choice response_format].freeze
            request_overrides = request_overrides.reject { |k, _v| reserved.include?(k) }

            new(
              tool_use_mode: tool_use_mode,
              tool_failure_policy: tool_failure_policy,
              tool_allowlist: tool_allowlist,
              tool_denylist: tool_denylist,
              policy: policy,
              policy_error_mode: policy_error_mode,
              event_context_keys: event_context_keys,
              fix_empty_final: fix_empty_final,
              fix_empty_final_user_text: fix_empty_final_user_text,
              fix_empty_final_disable_tools: fix_empty_final_disable_tools,
              fallback_retry_count: fallback_retry_count,
              max_tool_definitions_count: max_tool_definitions_count,
              max_tool_definitions_bytes: max_tool_definitions_bytes,
              max_tool_args_bytes: max_tool_args_bytes,
              max_tool_output_bytes: max_tool_output_bytes,
              max_tool_calls_per_turn: max_tool_calls_per_turn,
              tool_choice: tool_choice,
              message_transforms: message_transforms,
              tool_transforms: tool_transforms,
              response_transforms: response_transforms,
              tool_call_transforms: tool_call_transforms,
              tool_result_transforms: tool_result_transforms,
              request_overrides: request_overrides,
            )
          end

          def self.normalize_tool_choice(value)
            case value
            when nil
              nil
            when String
              s = value.strip
              s.empty? ? nil : s
            when Symbol
              value.to_s
            when Hash
              value
            else
              nil
            end
          end
          private_class_method :normalize_tool_choice

          def self.integer_or_default(value, default:)
            Integer(value)
          rescue ArgumentError, TypeError
            default
          end
          private_class_method :integer_or_default

          def self.positive_int_or_default(value, default:)
            return default if value.nil?

            i = Integer(value)
            i.positive? ? i : default
          rescue ArgumentError, TypeError
            default
          end
          private_class_method :positive_int_or_default

          def self.normalize_string_list(value)
            TavernKit::Utils.normalize_string_list(value)
          end
          private_class_method :normalize_string_list

          def self.normalize_string_array(value)
            Array(value).map { |v| v.to_s.strip }.reject(&:empty?)
          end
          private_class_method :normalize_string_array

          def self.normalize_policy_error_mode(value)
            mode = value.to_s.strip
            mode = "deny" if mode.empty?
            mode = mode.downcase.tr("-", "_")

            case mode
            when "deny"
              :deny
            when "allow"
              :allow
            when "raise"
              :raise
            else
              raise ArgumentError, "tool_calling.policy_error_mode must be :deny, :allow, or :raise"
            end
          end
          private_class_method :normalize_policy_error_mode

          def self.normalize_event_context_keys(value)
            keys =
              case value
              when nil
                []
              when Array
                value
              else
                [value]
              end

            keys
              .map { |v| v.to_s.strip }
              .reject(&:empty?)
              .map(&:to_sym)
              .uniq
          end
          private_class_method :normalize_event_context_keys
        end
    end
  end
end
