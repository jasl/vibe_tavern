# frozen_string_literal: true

require_relative "invocation"
require_relative "preprocessors"
require_relative "packs/silly_tavern"

module TavernKit
  module SillyTavern
    module Macro
      # Parser-based SillyTavern macro engine (Wave 3).
      #
      # The full implementation targets ST's experimental macro engine:
      # - scoped macros: {{if}}...{{/if}}
      # - macro flags: {{#if ...}} preserve whitespace
      # - typed args, list args, shorthand operators
      #
      # For now this is a small scaffold that runs preprocessors (legacy markers)
      # so downstream systems can safely adopt the V2Engine entrypoint early.
      class V2Engine < TavernKit::Macro::Engine::Base
        UNKNOWN_POLICIES = %i[keep empty].freeze

        def initialize(registry: Packs::SillyTavern.default_registry, unknown: :keep)
          unless UNKNOWN_POLICIES.include?(unknown)
            raise ArgumentError, "unknown must be one of: #{UNKNOWN_POLICIES.inspect}"
          end

          @registry = registry
          @unknown = unknown
        end

        def expand(text, environment:)
          return "" if text.nil?

          str = text.to_s
          return str if str.empty?

          preprocessed = Preprocessors.preprocess(str, environment: environment)
          out = expand_macros(preprocessed, environment)

          out = remove_unresolved_placeholders(out) if @unknown == :empty
          out
        end

        private

        def expand_macros(str, env)
          return str if str.empty?

          raw_content_hash = Invocation.stable_hash(str)

          str.gsub(/\{\{([^{}]*?)\}\}/m) do |match|
            offset = Regexp.last_match.begin(0) || 0
            inner = Regexp.last_match(1).to_s

            inv = parse_invocation(inner, env, raw_content_hash, offset)
            next match if inv.nil?

            replaced = evaluate_invocation(inv, fallback: match)
            replaced.nil? ? match : replaced.to_s
          end
        end

        def parse_invocation(inner, env, raw_content_hash, offset)
          s = inner.to_s.strip
          return nil if s.empty?

          # Closing tags belong to scoped macros (not implemented yet).
          return nil if s.start_with?("/")

          name, args = parse_name_and_args(s)
          return nil if name.nil? || name.empty?

          key = name.downcase
          Invocation.new(
            raw_inner: s,
            key: key,
            name: key.to_sym,
            args: args,
            offset: offset,
            raw_content_hash: raw_content_hash,
            environment: env,
          )
        end

        def parse_name_and_args(inner)
          if inner.include?("::")
            parts = inner.split("::", -1).map(&:to_s)
            name = parts.shift.to_s.strip
            args = parts.map { |p| p.to_s }
            [name, args.empty? ? nil : args]
          else
            name, rest = inner.split(/\s+/, 2)
            name = name.to_s.strip
            args = rest.nil? ? nil : [rest.to_s]
            [name, args]
          end
        end

        def evaluate_invocation(inv, fallback:)
          # Dynamic macros: only match argless `{{name}}`.
          if (inv.args.nil? || inv.args == []) && inv.environment.respond_to?(:dynamic_macros)
            dyn = inv.environment.dynamic_macros
            if dyn.is_a?(Hash)
              v = dyn[inv.key] || dyn[inv.key.to_s] || dyn[inv.key.to_sym]
              return normalize_value(v)
            end
          end

          defn = @registry.respond_to?(:get) ? @registry.get(inv.key) : nil
          return nil unless defn

          handler = defn.handler
          if handler.is_a?(Proc) && handler.arity == 0
            normalize_value(handler.call)
          else
            normalize_value(handler.call(inv))
          end
        rescue StandardError
          fallback.to_s
        end

        def normalize_value(value)
          case value
          when nil then ""
          when TrueClass then "true"
          when FalseClass then "false"
          else value.to_s
          end
        rescue StandardError
          ""
        end

        def remove_unresolved_placeholders(str)
          s = str.to_s
          return s if s.empty?

          prev = nil
          cur = s
          5.times do
            break if cur == prev

            prev = cur
            cur = cur.gsub(/\{\{[^{}]*\}\}/, "")
          end

          cur
        end
      end
    end
  end
end
