# frozen_string_literal: true

require_relative "../prompt_runner"
require_relative "../runner_config"
require_relative "../output_tags"
require_relative "parser"
require_relative "schema"
require_relative "validator"

module TavernKit
  module VibeTavern
    module Directives
      class Runner
        RESERVED_LLM_OPTIONS_KEYS = %i[model messages tools tool_choice stream stream_options].freeze

        ENVELOPE_OUTPUT_INSTRUCTIONS = <<~TEXT.strip
          Return a single JSON object and nothing else (no Markdown, no code fences).

          JSON shape:
          - assistant_text: String (always present)
          - directives: Array (always present)
          - Each directive: { type: String, payload: Object }
        TEXT

        def self.build(client:, runner_config:)
          prompt_runner = TavernKit::VibeTavern::PromptRunner.new(client: client)
          new(prompt_runner: prompt_runner, runner_config: runner_config)
        end

        def initialize(prompt_runner:, runner_config:)
          @prompt_runner = prompt_runner
          @runner_config = runner_config
        end

        # Runs a single structured directives request with fallbacks.
        #
        # The runner attempts modes in order:
        #   json_schema -> json_object -> prompt_only
        #
        # Each mode may be retried once (default) when parsing/validation fails.
        def run(
          history:,
          system: nil,
          variables_store: nil,
          strict: false,
          llm_options: nil,
          dialect: :openai,
          structured_output_options: nil,
          result_validator: nil
        )
          attempts = []
          capabilities = @runner_config.capabilities

          cfg = @runner_config.directives
          retry_budget = cfg.repair_retry_count

          base_llm_options =
            TavernKit::Utils.deep_merge_hashes(
              cfg.request_overrides,
              normalize_llm_options(llm_options),
            )
          structured_request_overrides = cfg.structured_request_overrides
          prompt_only_request_overrides = cfg.prompt_only_request_overrides

          base_structured_output_options =
            if structured_output_options.is_a?(Hash)
              TavernKit::Utils.assert_symbol_keys!(structured_output_options, path: "structured_output_options")
              structured_output_options.dup
            else
              {}
            end

          registry = base_structured_output_options[:registry]
          registry = nil unless registry.respond_to?(:types)

          schema_name =
            base_structured_output_options[:schema_name] || TavernKit::VibeTavern::Directives::Schema::NAME

          allowed_types =
            base_structured_output_options[:allowed_types] || (registry ? registry.types : nil)

          type_aliases =
            base_structured_output_options[:type_aliases] || (registry&.respond_to?(:type_aliases) ? registry.type_aliases : nil)

          payload_validator = base_structured_output_options[:payload_validator]

          output_instructions =
            base_structured_output_options[:output_instructions]
          output_instructions = output_instructions.to_s.strip
          if output_instructions.empty? && registry && registry.respond_to?(:instructions_text)
            output_instructions = registry.instructions_text.to_s.strip
          end

          base_system = system.to_s
          base_system =
            [
              base_system,
              ENVELOPE_OUTPUT_INSTRUCTIONS,
              output_instructions,
            ].map(&:to_s).map(&:strip).reject(&:empty?).join("\n\n")

          effective_modes = filter_supported_modes(cfg.modes, capabilities: capabilities, attempts: attempts)
          message_transforms = cfg.message_transforms
          response_transforms = cfg.response_transforms

          Array(effective_modes).each do |mode|
            mode = mode.to_s.strip.downcase.tr("-", "_").to_sym
            next unless TavernKit::VibeTavern::Directives::DEFAULT_MODES.include?(mode)

            response_format = response_format_for(mode, schema_name: schema_name, allowed_types: allowed_types)

            (1 + retry_budget).times do |attempt_index|
              repair = attempt_index.positive?
              system_text = base_system
              system_text = [system_text, repair_instructions(attempts.last)].join("\n\n") if repair

              mode_overrides = mode == :prompt_only ? prompt_only_request_overrides : structured_request_overrides
              llm_options_hash = TavernKit::Utils.deep_merge_hashes(base_llm_options, mode_overrides)

              llm_options_hash.delete(:response_format)
              llm_options_hash[:response_format] = response_format if response_format

              validate_llm_options!(llm_options_hash)

              prompt_request =
                @prompt_runner.build_request(
                  runner_config: @runner_config,
                  history: history,
                  system: system_text,
                  variables_store: variables_store,
                  strict: strict,
                  llm_options: llm_options_hash,
                  dialect: dialect,
                  message_transforms: message_transforms,
                  response_transforms: response_transforms,
                )

              prompt_result =
                begin
                  @prompt_runner.perform(prompt_request)
                rescue SimpleInference::Errors::HTTPError => e
                  attempts << attempt_http_error(mode, e, structured_output_unsupported: structured_output_unsupported_error?(e))
                  break
                end

              envelope, error, warnings =
                parse_directives_envelope(
                  prompt_result.assistant_message,
                  allowed_types: allowed_types,
                  type_aliases: type_aliases,
                  payload_validator: payload_validator,
                  max_bytes: base_structured_output_options.fetch(:max_bytes, nil),
                )

              attempts << attempt_structured(mode, prompt_result, envelope, error, warnings)

              if envelope
                candidate = ok_result(mode, prompt_result, envelope, warnings, attempts)
                reasons = validate_candidate(candidate, result_validator)
                if reasons.empty?
                  return candidate
                end

                attempts.last[:semantic_error] = { code: "ASSERTION_FAILED", reasons: reasons }
              end

              next if repair
            end
          end

          failure_result(attempts)
        end

        private

        def filter_supported_modes(modes, capabilities:, attempts:)
          normalized_modes =
            Array(modes)
              .map { |mode| mode.to_s.strip.downcase.tr("-", "_").to_sym }
              .select { |mode| TavernKit::VibeTavern::Directives::DEFAULT_MODES.include?(mode) }

          normalized_modes.each_with_object([]) do |mode, out|
            if mode_supported?(mode, capabilities)
              out << mode
              next
            end

            attempts << attempt_skipped_mode(mode)
          end
        end

        def mode_supported?(mode, capabilities)
          return true if mode == :prompt_only
          return false unless capabilities

          case mode
          when :json_schema
            capabilities.supports_response_format_json_schema
          when :json_object
            capabilities.supports_response_format_json_object
          else
            true
          end
        end

        def attempt_skipped_mode(mode)
          {
            mode: mode,
            ok: false,
            skipped: true,
            structured_output_error: {
              code: "CAPABILITY_UNSUPPORTED",
              message: "mode #{mode} is not supported by the current provider/model capabilities",
            },
            semantic_error: nil,
          }
        end

        def response_format_for(mode, schema_name:, allowed_types:)
          case mode
          when :json_schema
            TavernKit::VibeTavern::Directives::Schema.response_format(
              strict: true,
              name: schema_name,
              types: allowed_types,
            )
          when :json_object
            { type: "json_object" }
          when :prompt_only
            nil
          end
        end

        def structured_output_unsupported_error?(http_error)
          status = http_error.respond_to?(:status) ? http_error.status.to_i : 0
          return false unless [400, 422].include?(status)

          msg = http_error.message.to_s.downcase
          msg.include?("response_format") || msg.include?("structured") || msg.include?("json_schema") || msg.include?("json schema")
        end

        def repair_instructions(last_attempt)
          semantic_error = last_attempt.is_a?(Hash) ? last_attempt[:semantic_error] : nil
          semantic_reasons = semantic_error.is_a?(Hash) ? semantic_error[:reasons] : nil
          semantic_reasons = Array(semantic_reasons).map(&:to_s).map(&:strip).reject(&:empty?).uniq

          code =
            if semantic_error
              semantic_error[:code].to_s
            elsif last_attempt.is_a?(Hash) && last_attempt[:structured_output_error].is_a?(Hash)
              last_attempt[:structured_output_error][:code].to_s
            elsif last_attempt.is_a?(Hash) && last_attempt[:http_error]
              "HTTP_ERROR"
            end

          code = "UNKNOWN" if code.strip.empty?

          <<~TEXT.strip
            Your previous response was invalid (#{code}).
            #{semantic_reasons.any? ? "Problems: #{semantic_reasons.join("; ")}" : nil}
            Return the JSON object again, strictly following the required shape.
            Output JSON only.
          TEXT
        end

        def ok_result(mode, prompt_result, envelope, warnings, attempts)
          directives = Array(envelope.fetch("directives", nil)).select { |d| d.is_a?(Hash) }
          assistant_text = envelope.fetch("assistant_text", "").to_s
          assistant_text =
            TavernKit::VibeTavern::OutputTags.transform(
              assistant_text,
              config: @runner_config.output_tags,
            )

          normalized_envelope = envelope.dup
          normalized_envelope["assistant_text"] = assistant_text

          {
            ok: true,
            mode: mode,
            elapsed_ms: prompt_result.elapsed_ms,
            assistant_text: assistant_text,
            directives: directives,
            envelope: normalized_envelope,
            warnings: Array(warnings),
            attempts: attempts,
          }
        end

        def failure_result(attempts)
          last = attempts.last

          {
            ok: false,
            assistant_text: last.is_a?(Hash) ? last[:assistant_content_sample].to_s : "",
            directives: [],
            envelope: nil,
            warnings: [],
            attempts: attempts,
          }
        end

        def attempt_http_error(mode, http_error, structured_output_unsupported:)
          {
            mode: mode,
            ok: false,
            http_error: true,
            http_status: http_error.respond_to?(:status) ? http_error.status : nil,
            message: http_error.message.to_s,
            structured_output_unsupported: structured_output_unsupported == true,
          }
        end

        def attempt_structured(mode, prompt_result, envelope, error, warnings)
          content = prompt_result.assistant_message.fetch("content", nil).to_s
          {
            mode: mode,
            ok: !envelope.nil?,
            elapsed_ms: prompt_result.elapsed_ms,
            structured_output_error: error,
            structured_output_warnings: Array(warnings),
            semantic_error: nil,
            finish_reason: prompt_result.finish_reason,
            assistant_content_sample: content[0, 200],
          }
        end

        def parse_directives_envelope(assistant_message, allowed_types:, type_aliases:, payload_validator:, max_bytes:)
          tool_calls = assistant_message.fetch("tool_calls", nil)
          tool_calls_present =
            case tool_calls
            when Array
              tool_calls.any?
            when Hash
              tool_calls.any?
            else
              false
            end

          if tool_calls_present
            tool_calls_count =
              case tool_calls
              when Array
                tool_calls.size
              when Hash
                tool_calls.size
              else
                0
              end

            return [
                     nil,
                     {
                       code: "TOOL_CALLS_PRESENT",
                       message: "Tool calls are not allowed in directives mode; output JSON envelope only.",
                       tool_calls_count: tool_calls_count,
                     },
                     [],
                   ]
          end

          parsed =
            TavernKit::VibeTavern::Directives::Parser.parse_json(
              assistant_message.fetch("content", nil),
              max_bytes: normalize_max_bytes(max_bytes),
            )
          return [nil, parsed, []] unless parsed[:ok]

          validated =
            TavernKit::VibeTavern::Directives::Validator.validate(
              parsed[:value],
              allowed_types: allowed_types,
              type_aliases: type_aliases,
              payload_validator: payload_validator,
            )

          if validated[:ok]
            [validated[:value], nil, validated[:warnings]]
          else
            [nil, validated, []]
          end
        end
        private :parse_directives_envelope

        def normalize_max_bytes(raw_value)
          return TavernKit::VibeTavern::Directives::Parser::DEFAULT_MAX_BYTES if raw_value.nil?

          parsed = Integer(raw_value)
          return TavernKit::VibeTavern::Directives::Parser::DEFAULT_MAX_BYTES if parsed <= 0

          parsed
        rescue ArgumentError, TypeError
          TavernKit::VibeTavern::Directives::Parser::DEFAULT_MAX_BYTES
        end
        private :normalize_max_bytes

        def validate_candidate(candidate, result_validator)
          return [] unless result_validator&.respond_to?(:call)
          return [] unless candidate.is_a?(Hash)

          reasons =
            begin
              result_validator.call(candidate)
            rescue StandardError => e
              ["validator_error: #{e.class}: #{e.message}"]
            end

          Array(reasons).map(&:to_s).map(&:strip).reject(&:empty?).uniq
        end
        private :validate_candidate

        def normalize_llm_options(value)
          h = value.nil? ? {} : value
          raise ArgumentError, "llm_options must be a Hash" unless h.is_a?(Hash)

          TavernKit::Utils.assert_symbol_keys!(h, path: "llm_options")

          h.delete(:model)
          h.delete(:messages)
          h
        end

        def validate_llm_options!(llm_options)
          invalid = llm_options.keys & RESERVED_LLM_OPTIONS_KEYS
          raise ArgumentError, "directives llm_options contains reserved keys: #{invalid.inspect}" if invalid.any?
        end
      end
    end
  end
end
