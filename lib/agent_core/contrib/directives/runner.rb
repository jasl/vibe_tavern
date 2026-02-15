# frozen_string_literal: true

require_relative "../utils"
require_relative "schema"
require_relative "parser"
require_relative "validator"

module AgentCore
  module Contrib
    module Directives
      class Runner
        RESERVED_LLM_OPTIONS_KEYS = %i[model messages tools tool_choice stream stream_options].freeze

        def initialize(provider:, model:, llm_options_defaults:, directives_config:, capabilities: nil)
          @provider = provider
          @model = model.to_s
          @llm_options_defaults = normalize_llm_options_hash(llm_options_defaults)
          @directives = normalize_directives_config(directives_config)
          @capabilities = capabilities.is_a?(Hash) ? capabilities : {}
        end

        def run(
          history:,
          system: nil,
          structured_output_options: nil,
          result_validator: nil,
          token_counter: nil,
          context_window: nil,
          reserved_output_tokens: 0
        )
          attempts = []

          registry = structured_output_options.is_a?(Hash) ? structured_output_options.fetch(:registry, nil) : nil

          schema_name =
            if structured_output_options.is_a?(Hash)
              structured_output_options.fetch(:schema_name, nil) || AgentCore::Contrib::Directives::Schema::NAME
            else
              AgentCore::Contrib::Directives::Schema::NAME
            end

          allowed_types =
            if structured_output_options.is_a?(Hash)
              structured_output_options.fetch(:allowed_types, nil) || (registry&.respond_to?(:types) ? registry.types : nil)
            end

          type_aliases =
            if structured_output_options.is_a?(Hash)
              structured_output_options.fetch(:type_aliases, nil) || (registry&.respond_to?(:type_aliases) ? registry.type_aliases : nil)
            end

          payload_validator = structured_output_options.is_a?(Hash) ? structured_output_options.fetch(:payload_validator, nil) : nil

          output_instructions = structured_output_options.is_a?(Hash) ? structured_output_options.fetch(:output_instructions, nil) : nil
          output_instructions = output_instructions.to_s.strip
          if output_instructions.empty? && registry&.respond_to?(:instructions_text)
            output_instructions = registry.instructions_text.to_s.strip
          end

          base_system =
            [
              system.to_s,
              AgentCore::Contrib::Directives::ENVELOPE_OUTPUT_INSTRUCTIONS,
              output_instructions,
            ].map(&:to_s).map(&:strip).reject(&:empty?).join("\n\n")

          max_bytes = structured_output_options.is_a?(Hash) ? structured_output_options.fetch(:max_bytes, nil) : nil

          retry_budget = @directives.fetch(:repair_retry_count)

          @directives.fetch(:modes).each do |mode|
            mode_sym = mode.to_s.strip.downcase.tr("-", "_").to_sym
            next unless AgentCore::Contrib::Directives::DEFAULT_MODES.include?(mode_sym)

            unless mode_supported?(mode_sym)
              attempts << attempt_skipped_mode(mode_sym)
              next
            end

            response_format = response_format_for(mode_sym, schema_name: schema_name, allowed_types: allowed_types)

            (1 + retry_budget).times do |attempt_index|
              repair = attempt_index.positive?

              system_text = base_system
              system_text = [system_text, repair_instructions(attempts.last)].join("\n\n") if repair

              mode_overrides =
                if mode_sym == :prompt_only
                  @directives.fetch(:prompt_only_request_overrides)
                else
                  @directives.fetch(:structured_request_overrides)
                end

              llm_options =
                AgentCore::Contrib::Utils.deep_merge_hashes(
                  @llm_options_defaults,
                  @directives.fetch(:request_overrides),
                  mode_overrides,
                )

              llm_options.delete(:response_format)
              llm_options[:response_format] = response_format if response_format

              validate_llm_options!(llm_options)

              started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              assistant_message, assistant_text =
                begin
                  built_prompt =
                    AgentCore::PromptBuilder::BuiltPrompt.new(
                      system_prompt: system_text,
                      messages: Array(history),
                      tools: [],
                      options: { model: @model }.merge(llm_options),
                    )

                  run_result =
                    AgentCore::PromptRunner::Runner.new.run(
                      prompt: built_prompt,
                      provider: @provider,
                      max_turns: 1,
                      fix_empty_final: false,
                      token_counter: token_counter,
                      context_window: context_window,
                      reserved_output_tokens: reserved_output_tokens,
                    )

                  msg = run_result.final_message
                  [msg, msg&.text.to_s]
                rescue AgentCore::ProviderError => e
                  attempts << attempt_http_error(mode_sym, e, structured_output_unsupported: structured_output_unsupported_error?(e))
                  break
                rescue AgentCore::ContextWindowExceededError
                  raise
                rescue StandardError => e
                  if simple_inference_http_error?(e)
                    attempts << attempt_http_error(mode_sym, e, structured_output_unsupported: structured_output_unsupported_error?(e))
                    break
                  end

                  raise
                end
              elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

              envelope, error, warnings =
                parse_directives_envelope(
                  assistant_message,
                  assistant_text,
                  allowed_types: allowed_types,
                  type_aliases: type_aliases,
                  payload_validator: payload_validator,
                  max_bytes: max_bytes,
                )

              attempts << attempt_structured(mode_sym, assistant_text, envelope, error, warnings, elapsed_ms: elapsed_ms)

              if envelope
                candidate = ok_result(mode_sym, envelope, warnings, attempts, elapsed_ms: elapsed_ms)
                reasons = validate_candidate(candidate, result_validator)
                return candidate if reasons.empty?

                attempts.last[:semantic_error] = { code: "ASSERTION_FAILED", reasons: reasons }
              end
            end
          end

          failure_result(attempts)
        end

        private

        def normalize_llm_options_hash(value)
          h = value.nil? ? {} : value
          raise ArgumentError, "llm_options_defaults must be a Hash" unless h.is_a?(Hash)

          AgentCore::Utils.deep_symbolize_keys(h)
        end

        def normalize_directives_config(value)
          cfg = value.is_a?(Hash) ? AgentCore::Utils.deep_symbolize_keys(value) : {}

          modes = Array(cfg.fetch(:modes, AgentCore::Contrib::Directives::DEFAULT_MODES)).compact
          modes = modes.map { |m| m.to_s.strip.downcase.tr("-", "_").to_sym }
          modes = modes.select { |m| AgentCore::Contrib::Directives::DEFAULT_MODES.include?(m) }
          modes = AgentCore::Contrib::Directives::DEFAULT_MODES if modes.empty?

          repair_retry_count =
            Integer(
              cfg.fetch(:repair_retry_count, AgentCore::Contrib::Directives::DEFAULT_REPAIR_RETRY_COUNT),
              exception: false,
            )
          if repair_retry_count.nil? || repair_retry_count < 0
            repair_retry_count = AgentCore::Contrib::Directives::DEFAULT_REPAIR_RETRY_COUNT
          end

          {
            modes: modes,
            repair_retry_count: repair_retry_count,
            request_overrides: cfg.fetch(:request_overrides, {}),
            structured_request_overrides: cfg.fetch(:structured_request_overrides, {}),
            prompt_only_request_overrides: cfg.fetch(:prompt_only_request_overrides, {}),
          }
        end

        def mode_supported?(mode)
          case mode
          when :prompt_only
            true
          when :json_schema
            @capabilities.fetch(:supports_response_format_json_schema, true) == true
          when :json_object
            @capabilities.fetch(:supports_response_format_json_object, true) == true
          else
            true
          end
        end

        def response_format_for(mode, schema_name:, allowed_types:)
          case mode
          when :json_schema
            AgentCore::Contrib::Directives::Schema.response_format(
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
          status =
            if http_error.respond_to?(:status)
              http_error.status.to_i
            end
          return false unless [400, 422].include?(status)

          msg = http_error.message.to_s.downcase
          msg.include?("response_format") || msg.include?("structured") || msg.include?("json_schema") || msg.include?("json schema")
        end

        def simple_inference_http_error?(error)
          return false unless defined?(::SimpleInference::Errors::HTTPError)

          error.is_a?(::SimpleInference::Errors::HTTPError)
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
            else
              ""
            end
          code = "UNKNOWN" if code.strip.empty?

          <<~TEXT.strip
            Your previous response was invalid (#{code}).
            #{semantic_reasons.any? ? "Problems: #{semantic_reasons.join("; ")}" : nil}
            Return the JSON object again, strictly following the required shape.
            Output JSON only.
          TEXT
        end

        def ok_result(mode, envelope, warnings, attempts, elapsed_ms:)
          directives = Array(envelope.fetch("directives", nil)).select { |d| d.is_a?(Hash) }
          assistant_text = envelope.fetch("assistant_text", "").to_s

          normalized_envelope = envelope.dup
          normalized_envelope["assistant_text"] = assistant_text

          {
            ok: true,
            mode: mode,
            elapsed_ms: elapsed_ms,
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
            assistant_text: last.is_a?(Hash) ? last.fetch(:assistant_content_sample, "").to_s : "",
            directives: [],
            envelope: nil,
            warnings: [],
            attempts: attempts,
          }
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

        def attempt_structured(mode, assistant_text, envelope, error, warnings, elapsed_ms:)
          {
            mode: mode,
            ok: !envelope.nil?,
            elapsed_ms: elapsed_ms,
            structured_output_error: error,
            structured_output_warnings: Array(warnings),
            semantic_error: nil,
            assistant_content_sample: assistant_text.to_s[0, 200],
          }
        end

        def parse_directives_envelope(assistant_message, assistant_text, allowed_types:, type_aliases:, payload_validator:, max_bytes:)
          if assistant_message&.respond_to?(:has_tool_calls?) && assistant_message.has_tool_calls?
            tool_calls_count = Array(assistant_message.tool_calls).size

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
            AgentCore::Contrib::Directives::Parser.parse_json(
              assistant_text,
              max_bytes: normalize_max_bytes(max_bytes),
            )
          return [nil, parsed, []] unless parsed[:ok]

          validated =
            AgentCore::Contrib::Directives::Validator.validate(
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

        def normalize_max_bytes(raw_value)
          return AgentCore::Contrib::Directives::Parser::DEFAULT_MAX_BYTES if raw_value.nil?

          parsed = Integer(raw_value)
          return AgentCore::Contrib::Directives::Parser::DEFAULT_MAX_BYTES if parsed <= 0

          parsed
        rescue ArgumentError, TypeError
          AgentCore::Contrib::Directives::Parser::DEFAULT_MAX_BYTES
        end

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

        def validate_llm_options!(llm_options)
          invalid = llm_options.keys & RESERVED_LLM_OPTIONS_KEYS
          raise ArgumentError, "directives llm_options contains reserved keys: #{invalid.inspect}" if invalid.any?
        end
      end
    end
  end
end
