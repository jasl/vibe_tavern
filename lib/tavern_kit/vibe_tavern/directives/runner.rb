# frozen_string_literal: true

require_relative "presets"

module TavernKit
  module VibeTavern
    module Directives
      class Runner
        DEFAULT_REPAIR_RETRY_COUNT = 1

        DEFAULT_MODES = %i[json_schema json_object prompt_only].freeze

        ENVELOPE_OUTPUT_INSTRUCTIONS = <<~TEXT.strip
          Return a single JSON object and nothing else (no Markdown, no code fences).

          JSON shape:
          - assistant_text: String (always present)
          - directives: Array (always present)
          - Each directive: { type: String, payload: Object }
        TEXT

        def self.build(client:, model:, llm_options_defaults: nil, preset: nil)
          prompt_runner =
            TavernKit::VibeTavern::PromptRunner.new(
              client: client,
              model: model,
              llm_options_defaults: llm_options_defaults,
            )
          new(prompt_runner: prompt_runner, preset: preset)
        end

        def initialize(prompt_runner:, preset: nil)
          @prompt_runner = prompt_runner
          @preset = preset.is_a?(Hash) ? preset : nil
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
          runtime: nil,
          variables_store: nil,
          strict: false,
          llm_options: nil,
          dialect: :openai,
          message_transforms: nil,
          response_transforms: nil,
          structured_output_options: nil,
          preset: nil,
          modes: nil,
          repair_retry_count: nil,
          result_validator: nil
        )
          attempts = []

          effective_preset =
            TavernKit::VibeTavern::Directives::Presets.merge(
              @preset,
              preset,
            )

          raw_retry_count =
            repair_retry_count.nil? ? fetch_preset(effective_preset, :repair_retry_count) : repair_retry_count
          raw_retry_count = DEFAULT_REPAIR_RETRY_COUNT if raw_retry_count.nil?

          retry_budget =
            begin
              Integer(raw_retry_count)
            rescue ArgumentError, TypeError
              0
            end
          retry_budget = 0 if retry_budget.negative?

          base_llm_options =
            deep_merge_hashes(
              normalize_llm_options(fetch_preset(effective_preset, :request_overrides)),
              normalize_llm_options(llm_options),
            )
          structured_request_overrides = normalize_llm_options(fetch_preset(effective_preset, :structured_request_overrides))
          prompt_only_request_overrides = normalize_llm_options(fetch_preset(effective_preset, :prompt_only_request_overrides))

          base_structured_output_options = structured_output_options.is_a?(Hash) ? structured_output_options : {}

          registry = base_structured_output_options[:registry] || base_structured_output_options["registry"]
          registry = nil unless registry.respond_to?(:types)

          schema_name =
            base_structured_output_options[:schema_name] ||
              base_structured_output_options["schema_name"] ||
              TavernKit::VibeTavern::Directives::Schema::NAME

          allowed_types =
            base_structured_output_options[:allowed_types] ||
              base_structured_output_options["allowed_types"] ||
              (registry ? registry.types : nil)

          output_instructions =
            base_structured_output_options[:output_instructions] ||
              base_structured_output_options["output_instructions"]
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

          effective_modes = modes || fetch_preset(effective_preset, :modes) || DEFAULT_MODES

          message_transforms = fetch_preset(effective_preset, :message_transforms) if message_transforms.nil?
          response_transforms = fetch_preset(effective_preset, :response_transforms) if response_transforms.nil?

          Array(effective_modes).each do |mode|
            mode = mode.to_s.strip.downcase.tr("-", "_").to_sym
            next unless DEFAULT_MODES.include?(mode)

            response_format = response_format_for(mode, schema_name: schema_name, allowed_types: allowed_types)
            inject_response_format = mode != :prompt_only

            (1 + retry_budget).times do |attempt_index|
              repair = attempt_index.positive?
              system_text = base_system
              system_text = [system_text, repair_instructions(attempts.last)].join("\n\n") if repair

              mode_overrides = mode == :prompt_only ? prompt_only_request_overrides : structured_request_overrides
              llm_options_hash = deep_merge_hashes(base_llm_options, mode_overrides)

              llm_options_hash.delete(:response_format)
              llm_options_hash[:response_format] = response_format if response_format

              structured_opts =
                base_structured_output_options.merge(
                  inject_response_format: inject_response_format,
                )

              prompt_request =
                @prompt_runner.build_request(
                  history: history,
                  system: system_text,
                  runtime: runtime,
                  variables_store: variables_store,
                  strict: strict,
                  llm_options: llm_options_hash,
                  dialect: dialect,
                  message_transforms: message_transforms,
                  response_transforms: response_transforms,
                  structured_output: :directives_v1,
                  structured_output_options: structured_opts,
                )

              prompt_result =
                begin
                  @prompt_runner.perform(prompt_request)
                rescue SimpleInference::Errors::HTTPError => e
                  attempts << attempt_http_error(mode, e, structured_output_unsupported: structured_output_unsupported_error?(e))
                  break
                end

              envelope = prompt_result.structured_output
              error = prompt_result.structured_output_error
              warnings = prompt_result.structured_output_warnings

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
          {
            ok: true,
            mode: mode,
            elapsed_ms: prompt_result.elapsed_ms,
            assistant_text: envelope.fetch("assistant_text", "").to_s,
            directives: directives,
            envelope: envelope,
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

        def fetch_preset(preset, key)
          return nil unless preset.is_a?(Hash)

          preset[key] || preset[key.to_s]
        end

        def normalize_llm_options(value)
          h = value.is_a?(Hash) ? deep_symbolize_keys(value) : {}
          h.delete(:model)
          h.delete(:messages)
          h.delete(:tools)
          h.delete(:tool_choice)
          h.delete(:response_format)
          h
        end

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
      end
    end
  end
end
