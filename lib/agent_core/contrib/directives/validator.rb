# frozen_string_literal: true

require "json"

module AgentCore
  module Contrib
    module Directives
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
          env = envelope.is_a?(Hash) ? AgentCore::Utils.deep_stringify_keys(envelope) : {}
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
            d = directive.is_a?(Hash) ? AgentCore::Utils.deep_stringify_keys(directive) : nil
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
            unless prefixes.any? { |prefix| path.start_with?(prefix) }
              return { ok: false, code: "INVALID_PATCH_PATH", details: { index: idx, path: path } }
            end
            h["path"] = path

            needs_value = %w[set append insert].include?(action)
            if needs_value && !h.key?("value")
              return { ok: false, code: "MISSING_PATCH_VALUE", details: { index: idx, op: action } }
            end

            if action == "insert"
              raw_index = h.fetch("index", nil)
              index =
                begin
                  Integer(raw_index)
                rescue ArgumentError, TypeError
                  nil
                end
              unless index
                return { ok: false, code: "INVALID_PATCH_INDEX", details: { index: idx, raw_index: raw_index } }
              end

              h["index"] = index
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
          list = Array(value).map { |v| v.to_s.strip }.reject(&:empty?).uniq
          list.empty? ? nil : list
        end
        private_class_method :normalize_string_list

        def normalize_type_aliases(value, allowed_set:)
          aliases = value.is_a?(Hash) ? AgentCore::Utils.deep_stringify_keys(value) : {}

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

          wanted_token = tokenize_type(key)
          return nil if wanted_token.empty?

          matched_key = hash.keys.find { |k| tokenize_type(k) == wanted_token }
          matched_key ? hash[matched_key] : nil
        end
        private_class_method :fetch_key
      end
    end
  end
end
