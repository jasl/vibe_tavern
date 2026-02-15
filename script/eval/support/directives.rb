# frozen_string_literal: true

require "json"

require "agent_core"
require "simple_inference"

module VibeTavernEval
  module Directives
    DEFAULT_MODES = %i[json_schema json_object prompt_only].freeze
    DEFAULT_REPAIR_RETRY_COUNT = 1

    ENVELOPE_OUTPUT_INSTRUCTIONS = <<~TEXT.strip
      Return a single JSON object and nothing else (no Markdown, no code fences).

      JSON shape:
      - assistant_text: String (always present)
      - directives: Array (always present)
      - Each directive: { type: String, payload: Object }
    TEXT

    DirectiveDefinition =
      Data.define(:type, :description, :aliases) do
        def initialize(type:, description:, aliases: nil)
          super(
            type: type.to_s,
            description: description.to_s,
            aliases: normalize_aliases(aliases),
          )
        end

        def instruction_line
          t = type.to_s.strip
          d = description.to_s.strip
          return "" if t.empty?
          return t if d.empty?

          "#{t} (#{d})"
        end

        private

        def normalize_aliases(value)
          Array(value).map { |a| a.to_s.strip }.reject(&:empty?).uniq
        end
      end

    class Registry
      def initialize(definitions: [])
        @definitions =
          Array(definitions).map do |d|
            case d
            when DirectiveDefinition
              d
            when Hash
              DirectiveDefinition.new(
                type: d.fetch(:type),
                description: d.fetch(:description, nil),
                aliases: d.fetch(:aliases, nil),
              )
            else
              raise ArgumentError, "Invalid directive definition: #{d.inspect}"
            end
          end
      end

      def definitions = @definitions

      def types
        definitions.map(&:type).map { |t| t.to_s.strip }.reject(&:empty?).uniq
      end

      def type_aliases
        definitions.each_with_object({}) do |d, out|
          canonical = d.type.to_s.strip
          next if canonical.empty?

          Array(d.aliases).each do |a|
            alias_name = a.to_s.strip
            next if alias_name.empty?

            out[alias_name] ||= canonical
          end
        end
      end

      def instructions_text
        lines = definitions.map(&:instruction_line).map(&:strip).reject(&:empty?)
        return "" if lines.empty?

        [
          "Allowed directive types:",
          *lines.map { |l| "- #{l}" },
        ].join("\n")
      end
    end

    module Schema
      NAME = "tavern_directives"

      module_function

      def response_format(strict: true, name: NAME, types: nil)
        {
          type: "json_schema",
          json_schema: {
            name: name.to_s,
            strict: strict == true,
            schema: schema_hash(types: types),
          },
        }
      end

      def schema_hash(types: nil)
        type_property = { type: "string" }
        enum = normalize_type_enum(types)
        type_property[:enum] = enum if enum

        {
          type: "object",
          additionalProperties: false,
          required: ["assistant_text", "directives"],
          properties: {
            assistant_text: { type: "string" },
            directives: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                required: ["type", "payload"],
                properties: {
                  type: type_property,
                  payload: {
                    type: "object",
                    additionalProperties: true,
                  },
                },
              },
            },
          },
        }
      end

      def normalize_type_enum(types)
        list = Array(types).map { |t| t.to_s.strip }.reject(&:empty?).uniq
        list.empty? ? nil : list
      end
      private_class_method :normalize_type_enum
    end

    module Parser
      DEFAULT_MAX_BYTES = 200_000

      module_function

      def parse_json(content, max_bytes: DEFAULT_MAX_BYTES)
        return { ok: true, value: content } if content.is_a?(Hash)

        str = content.to_s.strip
        return { ok: false, code: "EMPTY", error: "empty content" } if str.empty?
        if str.bytesize > max_bytes
          return { ok: false, code: "TOO_LARGE", error: "content too large", details: { max_bytes: max_bytes } }
        end

        candidate = unwrap_content(str)
        parse_object(candidate) || parse_object(extract_first_json_object(candidate)) || invalid_json(candidate)
      end

      def unwrap_content(str)
        s = unwrap_xmlish_tag(str, "directives") || unwrap_xmlish_tag(str, "json") || str
        unwrap_code_fence(s) || s
      end
      private_class_method :unwrap_content

      def unwrap_xmlish_tag(str, tag)
        m = str.match(%r{<#{Regexp.escape(tag)}>\s*(.+?)\s*</#{Regexp.escape(tag)}>}m)
        m ? m[1].to_s : nil
      end
      private_class_method :unwrap_xmlish_tag

      def unwrap_code_fence(str)
        m = str.match(/\A```(?:json)?\s*(.+?)\s*```\z/m)
        m ? m[1].to_s : nil
      end
      private_class_method :unwrap_code_fence

      def parse_object(str)
        return nil if str.nil?

        obj = JSON.parse(str)
        return { ok: true, value: obj } if obj.is_a?(Hash)

        { ok: false, code: "NOT_OBJECT", error: "root must be a JSON object" }
      rescue JSON::ParserError, TypeError
        nil
      end
      private_class_method :parse_object

      def invalid_json(str)
        { ok: false, code: "INVALID_JSON", error: "unable to parse JSON", details: { sample: str[0, 200] } }
      end
      private_class_method :invalid_json

      def extract_first_json_object(str)
        input = str.to_s
        start = input.index("{")
        return nil unless start

        in_string = false
        escaped = false
        depth = 0

        input.chars.each_with_index do |ch, idx|
          next if idx < start

          if in_string
            if escaped
              escaped = false
            elsif ch == "\\"
              escaped = true
            elsif ch == "\""
              in_string = false
            end
            next
          end

          case ch
          when "\""
            in_string = true
          when "{"
            depth += 1
          when "}"
            depth -= 1
            return input[start..idx] if depth.zero?
          end
        end

        nil
      end
      private_class_method :extract_first_json_object
    end

    module Validator
      ALLOWED_PATCH_OPS = %w[set delete append insert].freeze
      PATCH_OP_ALIASES = {
        "add" => "set",
        "replace" => "set",
        "remove" => "delete",
        "rm" => "delete",
        "push" => "append",
      }.freeze
      DEFAULT_ALLOWED_PATCH_PATH_PREFIXES = %w[/draft/ /ui_state/].freeze

      module_function

      def validate(envelope, allowed_types: nil, type_aliases: nil, payload_validator: nil)
        env = envelope.is_a?(Hash) ? envelope : {}
        assistant_text = fetch_key(env, "assistant_text")
        directives = fetch_key(env, "directives")

        return err("MISSING_ASSISTANT_TEXT") unless assistant_text.is_a?(String)
        return err("MISSING_DIRECTIVES") unless directives.is_a?(Array)

        allowed_types = normalize_string_list(allowed_types)
        allowed_set = allowed_types ? allowed_types.to_h { |t| [t, true] } : nil
        canonical_by_token = allowed_types ? allowed_types.to_h { |t| [tokenize_type(t), t] } : {}
        aliases_by_token = normalize_type_aliases(type_aliases, allowed_set: allowed_set)

        warnings = []
        normalized = []

        directives.each_with_index do |directive, idx|
          d = directive.is_a?(Hash) ? directive : nil
          unless d
            warnings << { code: "DIRECTIVE_NOT_OBJECT", index: idx }
            next
          end

          type_raw = fetch_key(d, "type")
          type_str = type_raw.to_s.strip
          token = tokenize_type(type_str)
          if token.empty?
            warnings << { code: "MISSING_TYPE", index: idx }
            next
          end

          canonical =
            canonical_by_token[token] ||
              aliases_by_token[token] ||
              (allowed_set ? nil : type_str)

          unless canonical
            warnings << { code: "UNKNOWN_DIRECTIVE_TYPE", index: idx, type: type_str }
            next
          end

          if allowed_set && !allowed_set.key?(canonical)
            warnings << { code: "DISALLOWED_DIRECTIVE_TYPE", index: idx, type: canonical }
            next
          end

          payload_raw = fetch_key(d, "payload")
          payload = payload_raw.is_a?(Hash) ? AgentCore::Utils.deep_stringify_keys(payload_raw) : nil
          unless payload
            warnings << { code: "MISSING_PAYLOAD", index: idx, type: canonical }
            next
          end

          if payload_validator&.respond_to?(:call)
            payload_error =
              begin
                payload_validator.call(canonical, payload)
              rescue StandardError => e
                { code: "PAYLOAD_VALIDATOR_ERROR", details: { error: "#{e.class}: #{e.message}" } }
              end

            if payload_error
              warnings << normalize_payload_error(payload_error).merge(index: idx, type: canonical)
              next
            end
          end

          normalized << { "type" => canonical, "payload" => payload }
        end

        ok(
          {
            "assistant_text" => assistant_text,
            "directives" => normalized,
          },
          warnings: warnings,
        )
      end

      def validate_patch_ops(ops, allowed_path_prefixes: DEFAULT_ALLOWED_PATCH_PATH_PREFIXES)
        result = normalize_patch_ops(ops, allowed_path_prefixes: allowed_path_prefixes)
        return nil if result[:ok]

        { code: result[:code], details: result[:details] }
      end

      def normalize_patch_ops(ops, allowed_path_prefixes: DEFAULT_ALLOWED_PATCH_PATH_PREFIXES)
        list =
          case ops
          when Array
            ops
          when Hash
            [ops]
          when String
            parse_patch_ops_json_string(ops)
          else
            []
          end
        return { ok: false, code: "MISSING_OPS" } if list.empty?

        prefixes = Array(allowed_path_prefixes).map(&:to_s).reject(&:empty?)
        prefixes = DEFAULT_ALLOWED_PATCH_PATH_PREFIXES if prefixes.empty?
        default_prefix = prefixes.include?("/draft/") ? "/draft/" : prefixes.first

        normalized_ops = []

        list.each_with_index do |op, idx|
          h = op.is_a?(Hash) ? AgentCore::Utils.deep_stringify_keys(op) : {}

          action_raw = h.fetch("op", "").to_s.strip
          action_raw = infer_patch_op(h) if action_raw.empty?
          action = normalize_patch_op(action_raw)
          unless ALLOWED_PATCH_OPS.include?(action)
            return { ok: false, code: "INVALID_PATCH_OP", details: { index: idx, op: action_raw } }
          end

          path = normalize_patch_path(h.fetch("path", nil), default_prefix: default_prefix)
          unless prefixes.any? { |p| path.start_with?(p) }
            return { ok: false, code: "INVALID_PATCH_PATH", details: { index: idx, path: path } }
          end
          h["path"] = path

          needs_value = %w[set append insert].include?(action)
          if needs_value && !h.key?("value")
            return { ok: false, code: "MISSING_PATCH_VALUE", details: { index: idx, op: action } }
          end

          if action == "insert"
            raw_index = h.fetch("index", nil)
            i =
              begin
                Integer(raw_index)
              rescue ArgumentError, TypeError
                nil
              end
            return { ok: false, code: "INVALID_PATCH_INDEX", details: { index: idx, raw_index: raw_index } } unless i

            h["index"] = i
          end

          h["op"] = action
          normalized_ops << h
        end

        { ok: true, ops: normalized_ops }
      end

      def normalize_patch_op(value)
        raw = value.to_s.strip.downcase
        PATCH_OP_ALIASES.fetch(raw, raw)
      end
      private_class_method :normalize_patch_op

      def infer_patch_op(op_hash)
        h = op_hash.is_a?(Hash) ? op_hash : {}
        h.key?("value") ? "set" : "delete"
      end
      private_class_method :infer_patch_op

      def normalize_patch_path(value, default_prefix:)
        path = value.to_s.strip
        path = path.sub(/\A["'`]+\s*/, "").sub(/\s*["'`]+\z/, "")
        return path if path.start_with?("/")

        if path.start_with?("draft/") || path.start_with?("ui_state/")
          return "/#{path}"
        end

        prefix = default_prefix.to_s
        prefix = "/draft/" if prefix.empty?
        prefix = "#{prefix}/" unless prefix.end_with?("/")

        "#{prefix}#{path}"
      end
      private_class_method :normalize_patch_path

      def parse_patch_ops_json_string(value)
        str = value.to_s.strip
        return [] if str.empty?

        begin
          parsed = JSON.parse(str)
          return parsed if parsed.is_a?(Array)
          return [parsed] if parsed.is_a?(Hash)
        rescue JSON::ParserError
          nil
        end

        []
      end
      private_class_method :parse_patch_ops_json_string

      def ok(value, warnings:)
        {
          ok: true,
          value: value,
          warnings: Array(warnings),
        }
      end

      def err(code, details = {})
        {
          ok: false,
          code: code.to_s,
          details: details,
        }
      end

      def normalize_payload_error(value)
        case value
        when String
          { code: value }
        when Hash
          h = AgentCore::Utils.symbolize_keys(value)
          code = h.fetch(:code, "PAYLOAD_INVALID").to_s
          code = "PAYLOAD_INVALID" if code.strip.empty?
          details = h.fetch(:details, nil)
          out = { code: code }
          out[:details] = details if details.is_a?(Hash)
          out
        else
          { code: "PAYLOAD_INVALID" }
        end
      end
      private_class_method :normalize_payload_error

      def tokenize_type(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "_").delete_prefix("_").delete_suffix("_")
      end
      private_class_method :tokenize_type

      def normalize_string_list(value)
        list =
          Array(value).map { |v| v.to_s.strip }.reject(&:empty?).uniq
        list.empty? ? nil : list
      end
      private_class_method :normalize_string_list

      def normalize_type_aliases(value, allowed_set:)
        aliases = value.is_a?(Hash) ? value : {}

        aliases.each_with_object({}) do |(alias_name, canonical), out|
          alias_token = tokenize_type(alias_name)
          next if alias_token.empty?

          canonical_str = canonical.to_s.strip
          next if canonical_str.empty?
          next if allowed_set && !allowed_set.key?(canonical_str)

          out[alias_token] ||= canonical_str
        end
      end
      private_class_method :normalize_type_aliases

      def fetch_key(hash, key)
        return nil unless hash.is_a?(Hash)

        return hash[key] if hash.key?(key)

        if key.is_a?(String)
          sym = key.to_sym
          return hash[sym] if hash.key?(sym)
        elsif key.is_a?(Symbol)
          str = key.to_s
          return hash[str] if hash.key?(str)
        end

        wanted_token = tokenize_type(key)
        return nil if wanted_token.empty?

        matched_key = hash.keys.find { |k| tokenize_type(k) == wanted_token }
        matched_key ? hash[matched_key] : nil
      end
      private_class_method :fetch_key
    end

    class Runner
      RESERVED_LLM_OPTIONS_KEYS = %i[model messages tools tool_choice stream stream_options].freeze

      def initialize(provider:, model:, llm_options_defaults:, directives_config:, capabilities: nil)
        @provider = provider
        @model = model.to_s
        @llm_options_defaults = normalize_llm_options_hash(llm_options_defaults)
        @directives = normalize_directives_config(directives_config)
        @capabilities = capabilities.is_a?(Hash) ? capabilities : {}
      end

      def run(history:, system: nil, structured_output_options: nil, result_validator: nil)
        attempts = []

        registry = structured_output_options.is_a?(Hash) ? structured_output_options.fetch(:registry, nil) : nil

        schema_name =
          if structured_output_options.is_a?(Hash)
            structured_output_options.fetch(:schema_name, nil) || VibeTavernEval::Directives::Schema::NAME
          else
            VibeTavernEval::Directives::Schema::NAME
          end

        allowed_types =
          if structured_output_options.is_a?(Hash)
            structured_output_options.fetch(:allowed_types, nil) || (registry&.respond_to?(:types) ? registry.types : nil)
          else
            nil
          end

        type_aliases =
          if structured_output_options.is_a?(Hash)
            structured_output_options.fetch(:type_aliases, nil) || (registry&.respond_to?(:type_aliases) ? registry.type_aliases : nil)
          else
            nil
          end

        payload_validator = structured_output_options.is_a?(Hash) ? structured_output_options.fetch(:payload_validator, nil) : nil

        output_instructions =
          if structured_output_options.is_a?(Hash)
            structured_output_options.fetch(:output_instructions, nil)
          end
        output_instructions = output_instructions.to_s.strip
        if output_instructions.empty? && registry&.respond_to?(:instructions_text)
          output_instructions = registry.instructions_text.to_s.strip
        end

        base_system =
          [
            system.to_s,
            VibeTavernEval::Directives::ENVELOPE_OUTPUT_INSTRUCTIONS,
            output_instructions,
          ].map(&:to_s).map(&:strip).reject(&:empty?).join("\n\n")

        max_bytes =
          if structured_output_options.is_a?(Hash)
            structured_output_options.fetch(:max_bytes, nil)
          end

        retry_budget = @directives.fetch(:repair_retry_count)

        @directives.fetch(:modes).each do |mode|
          mode_sym = mode.to_s.strip.downcase.tr("-", "_").to_sym
          next unless VibeTavernEval::Directives::DEFAULT_MODES.include?(mode_sym)

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
              deep_merge_hashes(
                @llm_options_defaults,
                @directives.fetch(:request_overrides),
                mode_overrides,
              )

            llm_options.delete(:response_format)
            llm_options[:response_format] = response_format if response_format

            validate_llm_options!(llm_options)

            prompt_messages = []
            prompt_messages << AgentCore::Message.new(role: :system, content: system_text) unless system_text.strip.empty?
            prompt_messages.concat(Array(history))

            started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            response =
              begin
                @provider.chat(
                  messages: prompt_messages,
                  model: @model,
                  tools: nil,
                  stream: false,
                  **llm_options,
                )
              rescue SimpleInference::Errors::HTTPError => e
                attempts << attempt_http_error(mode_sym, e, structured_output_unsupported: structured_output_unsupported_error?(e))
                break
              end
            elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

            assistant_message = response.respond_to?(:message) ? response.message : nil
            assistant_text = assistant_message&.text.to_s

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

        modes = Array(cfg.fetch(:modes, VibeTavernEval::Directives::DEFAULT_MODES)).compact
        modes = modes.map { |m| m.to_s.strip.downcase.tr("-", "_").to_sym }
        modes = modes.select { |m| VibeTavernEval::Directives::DEFAULT_MODES.include?(m) }
        modes = VibeTavernEval::Directives::DEFAULT_MODES if modes.empty?

        repair_retry_count = Integer(cfg.fetch(:repair_retry_count, VibeTavernEval::Directives::DEFAULT_REPAIR_RETRY_COUNT), exception: false)
        repair_retry_count = VibeTavernEval::Directives::DEFAULT_REPAIR_RETRY_COUNT if repair_retry_count.nil? || repair_retry_count < 0

        {
          modes: modes,
          repair_retry_count: repair_retry_count,
          request_overrides: cfg.fetch(:request_overrides, {}),
          structured_request_overrides: cfg.fetch(:structured_request_overrides, {}),
          prompt_only_request_overrides: cfg.fetch(:prompt_only_request_overrides, {}),
        }
      end

      def deep_merge_hashes(*hashes)
        hashes.reduce({}) do |acc, h|
          merge_two_hashes(acc, h)
        end
      end

      def merge_two_hashes(left, right)
        out = (left.is_a?(Hash) ? left : {}).dup
        (right.is_a?(Hash) ? right : {}).each do |k, v|
          if out[k].is_a?(Hash) && v.is_a?(Hash)
            out[k] = merge_two_hashes(out[k], v)
          else
            out[k] = v
          end
        end
        out
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
          VibeTavernEval::Directives::Schema.response_format(
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
          VibeTavernEval::Directives::Parser.parse_json(
            assistant_text,
            max_bytes: normalize_max_bytes(max_bytes),
          )
        return [nil, parsed, []] unless parsed[:ok]

        validated =
          VibeTavernEval::Directives::Validator.validate(
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
        return VibeTavernEval::Directives::Parser::DEFAULT_MAX_BYTES if raw_value.nil?

        parsed = Integer(raw_value)
        return VibeTavernEval::Directives::Parser::DEFAULT_MAX_BYTES if parsed <= 0

        parsed
      rescue ArgumentError, TypeError
        VibeTavernEval::Directives::Parser::DEFAULT_MAX_BYTES
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
