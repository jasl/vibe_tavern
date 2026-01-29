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
      # The implementation grows with characterization tests to avoid drifting
      # from real ST behavior.
      class V2Engine < TavernKit::Macro::Engine::Base
        TextNode = Data.define(:text)
        MacroNode = Data.define(:raw_inner, :offset)
        IfNode = Data.define(:condition, :preserve_whitespace, :then_nodes, :else_nodes)

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
          raw_content_hash = Invocation.stable_hash(preprocessed)
          original_once = build_original_once(environment)

          nodes = parse_template(preprocessed)
          out = evaluate_nodes(nodes, environment, raw_content_hash: raw_content_hash, original_once: original_once)

          out = remove_unresolved_placeholders(out) if @unknown == :empty
          out
        end

        private

        def parse_template(str)
          nodes, = parse_nodes(str, 0, terminators: nil)
          nodes
        end

        def parse_nodes(str, start_idx, terminators:)
          nodes = []
          i = start_idx

          while i < str.length
            open = str.index("{{", i)
            if open.nil?
              tail = str[i..]
              nodes << TextNode.new(text: tail) if tail && !tail.empty?
              return [nodes, str.length, nil]
            end

            nodes << TextNode.new(text: str[i...open]) if open > i

            close = str.index("}}", open + 2)
            if close.nil?
              nodes << TextNode.new(text: str[open..])
              return [nodes, str.length, nil]
            end

            raw_inner = str[(open + 2)...close].to_s
            normalized = raw_inner.strip
            key = normalized.downcase

            if terminators && terminators.include?(key)
              return [nodes, close + 2, key]
            end

            if_info = parse_if_open(normalized)
            if if_info
              then_nodes, next_idx, term = parse_nodes(str, close + 2, terminators: %w[else /if])
              else_nodes = []
              if term == "else"
                else_nodes, next_idx, = parse_nodes(str, next_idx, terminators: %w[/if])
              end

              nodes << IfNode.new(
                condition: if_info[:condition],
                preserve_whitespace: if_info[:preserve_whitespace],
                then_nodes: then_nodes,
                else_nodes: else_nodes,
              )

              i = next_idx
            else
              nodes << MacroNode.new(raw_inner: raw_inner, offset: open)
              i = close + 2
            end
          end

          [nodes, i, nil]
        end

        def parse_if_open(normalized)
          s = normalized.to_s
          preserve = false
          if s.start_with?("#")
            preserve = true
            s = s.delete_prefix("#").lstrip
          end

          return nil unless s.match?(/\Aif\b/i)

          condition = s.sub(/\Aif\b/i, "").strip
          { preserve_whitespace: preserve, condition: condition }
        end

        def evaluate_nodes(nodes, env, raw_content_hash:, original_once:)
          out = +""

          nodes.each do |node|
            case node
            when TextNode
              out << node.text.to_s
            when MacroNode
              out << evaluate_macro_node(node, env, raw_content_hash: raw_content_hash, original_once: original_once)
            when IfNode
              out << evaluate_if_node(node, env, raw_content_hash: raw_content_hash, original_once: original_once)
            else
              out << node.to_s
            end
          end

          out
        end

        def evaluate_if_node(node, env, raw_content_hash:, original_once:)
          truthy = evaluate_condition(node.condition, env)
          chosen = truthy ? node.then_nodes : node.else_nodes

          rendered = evaluate_nodes(chosen, env, raw_content_hash: raw_content_hash, original_once: original_once)
          node.preserve_whitespace == true ? rendered : rendered.strip
        end

        def evaluate_condition(expr, env)
          s = expr.to_s.strip
          return false if s.empty?

          if s.start_with?(".")
            truthy_value(env.respond_to?(:get_var) ? env.get_var(s.delete_prefix("."), scope: :local) : nil)
          elsif s.start_with?("$")
            truthy_value(env.respond_to?(:get_var) ? env.get_var(s.delete_prefix("$"), scope: :global) : nil)
          else
            truthy_value(s)
          end
        end

        def truthy_value(value)
          case value
          when nil then false
          when true then true
          when false then false
          else
            s = value.to_s.strip
            return false if s.empty?
            return false if s.casecmp("false").zero?
            return false if s == "0"

            true
          end
        end

        def evaluate_macro_node(node, env, raw_content_hash:, original_once:)
          fallback = "{{#{node.raw_inner}}}"
          variable_out = evaluate_variable_shorthand(node.raw_inner, env)
          return variable_out unless variable_out.nil?

          inv = parse_invocation(node.raw_inner, env, raw_content_hash, node.offset)
          return fallback if inv.nil?

          replaced = evaluate_invocation(inv, fallback: fallback, original_once: original_once)
          replaced.nil? ? fallback : replaced.to_s
        end

        def evaluate_variable_shorthand(raw_inner, env)
          s = raw_inner.to_s.strip
          return nil unless s.start_with?(".", "$")

          m = s.match(/\A(?<scope>[.$])(?<name>[A-Za-z0-9_]+)\s*(?<op>\+\=|=|\+\+|--)?\s*(?<rest>.*)\z/)
          return nil unless m

          scope = m[:scope] == "$" ? :global : :local
          name = m[:name].to_s
          op = m[:op]
          rest = m[:rest].to_s.strip

          return nil unless env.respond_to?(:get_var) && env.respond_to?(:set_var)

          case op
          when nil
            normalize_value(env.get_var(name, scope: scope))
          when "+="
            apply_var_add(env, name, scope: scope, value: rest)
          when "="
            env.set_var(name, rest, scope: scope)
            ""
          else
            nil
          end
        rescue StandardError
          nil
        end

        def apply_var_add(env, name, scope:, value:)
          current = env.get_var(name, scope: scope)
          rhs_num = coerce_number(value)
          cur_num = coerce_number(current)

          if !rhs_num.nil? && (current.nil? || !cur_num.nil?)
            env.set_var(name, (cur_num || 0) + rhs_num, scope: scope)
            return ""
          end

          env.set_var(name, "#{current}#{value}", scope: scope)
          ""
        end

        def coerce_number(value)
          return value if value.is_a?(Numeric)

          s = value.to_s.strip
          return nil if s.empty?

          Integer(s)
        rescue ArgumentError
          Float(s)
        rescue StandardError
          nil
        end

        def parse_invocation(inner, env, raw_content_hash, offset)
          s = inner.to_s.strip
          return nil if s.empty?

          # Closing tags belong to scoped macros.
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

        def evaluate_invocation(inv, fallback:, original_once:)
          if inv.key == "original"
            return original_once ? original_once.call : ""
          end

          # Dynamic macros: only match argless `{{name}}`.
          if (inv.args.nil? || inv.args == []) && inv.environment.respond_to?(:dynamic_macros)
            dyn = inv.environment.dynamic_macros
            if dyn.is_a?(Hash)
              if dyn.key?(inv.key)
                return normalize_value(dyn[inv.key])
              end
              if dyn.key?(inv.key.to_s)
                return normalize_value(dyn[inv.key.to_s])
              end
              if dyn.key?(inv.key.to_sym)
                return normalize_value(dyn[inv.key.to_sym])
              end
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

        def build_original_once(env)
          return nil unless env.respond_to?(:original)

          original = env.original
          return nil if original.nil? || original.to_s.empty?

          used = false
          lambda do
            return "" if used

            used = true
            original.to_s
          end
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
