# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolCalling
      class ToolDispatcher
        DEFAULT_TOOL_NAME_ALIASES = {}.freeze

        class PolicyError < StandardError; end

        attr_accessor :on_policy_error

        def initialize(
          executor:,
          registry:,
          expose: :model,
          tool_name_aliases: nil,
          policy: nil,
          policy_context: nil,
          policy_error_mode: :deny,
          on_policy_error: nil
        )
          @executor = executor
          @registry = registry
          @expose = expose
          @tool_name_aliases = tool_name_aliases || DEFAULT_TOOL_NAME_ALIASES
          @executor_accepts_tool_call_id = nil

          @policy = policy
          @policy_context = policy_context
          @policy_error_mode = normalize_policy_error_mode(policy_error_mode)
          @on_policy_error = on_policy_error.respond_to?(:call) ? on_policy_error : nil
        end

        def execute(name:, args:, tool_call_id: nil)
          name = normalize_tool_name(name.to_s.strip)
          args = args.is_a?(Hash) ? args : {}

          unless @registry.include?(name, expose: @expose)
            return error_envelope(name, code: "TOOL_NOT_ALLOWED", message: "Tool not allowed: #{name}")
          end

          tool_call_id = tool_call_id.to_s
          policy_result = evaluate_policy(name: name, args: args, tool_call_id: tool_call_id)
          return policy_result if policy_result

          result =
            if !tool_call_id.empty? && executor_accepts_tool_call_id?
              @executor.call(name: name, args: args, tool_call_id: tool_call_id)
            else
              @executor.call(name: name, args: args)
            end

          # Allow executors to return already-normalized envelopes, but don't
          # require it for simple implementations.
          if result.is_a?(Hash)
            normalized = TavernKit::Utils.deep_symbolize_keys(result)
            return normalize_envelope(name, normalized) if normalized.key?(:ok)
          end

          ok_envelope(name, result)
        rescue PolicyError
          raise
        rescue ArgumentError => e
          error_envelope(name, code: "ARGUMENT_ERROR", message: e.message)
        rescue StandardError => e
          # Unexpected programming error: surface clearly so tests/debugging can catch it.
          error_envelope(name, code: "INTERNAL_ERROR", message: "#{e.class}: #{e.message}")
        end

        private

        def ok_envelope(name, data)
          data = TavernKit::Utils.deep_symbolize_keys(data) if data.is_a?(Hash)

          {
            ok: true,
            tool_name: name,
            data: data.is_a?(Hash) ? data : { value: data },
            warnings: [],
            errors: [],
          }
        end

        def error_envelope(name, code:, message:)
          {
            ok: false,
            tool_name: name,
            data: {},
            warnings: [],
            errors: [
              {
                code: code,
                message: message.to_s,
              },
            ],
          }
        end

        def normalize_tool_name(name)
          normalized = @tool_name_aliases.fetch(name, name)

          # Some providers/models may output `foo.bar` even if we recommend `_`.
          # If the dotted name is not registered but the underscored variant is,
          # accept it for robustness.
          if normalized.include?(".")
            underscored = normalized.tr(".", "_")
            return underscored if @registry.include?(underscored, expose: @expose)
          end

          normalized
        end

        def executor_accepts_tool_call_id?
          return @executor_accepts_tool_call_id unless @executor_accepts_tool_call_id.nil?

          params = callable_parameters(@executor)
          @executor_accepts_tool_call_id =
            params.any? do |type, name|
              type == :keyrest || (%i[key keyreq].include?(type) && name == :tool_call_id)
            end
        end

        def callable_parameters(callable)
          return [] unless callable

          if callable.respond_to?(:parameters)
            callable.parameters
          else
            callable.method(:call).parameters
          end
        rescue NameError, TypeError
          []
        end

        def normalize_envelope(default_tool_name, value)
          raw = value.is_a?(Hash) ? value : {}

          ok = raw.fetch(:ok, false)
          tool_name = raw.fetch(:tool_name, nil)
          data = raw.fetch(:data, nil)
          warnings = raw.fetch(:warnings, nil)
          errors = raw.fetch(:errors, nil)

          {
            ok: ok == true,
            tool_name: tool_name.to_s.strip.empty? ? default_tool_name.to_s : tool_name.to_s,
            data: data.is_a?(Hash) ? data : (data.nil? ? {} : { value: data }),
            warnings: warnings.is_a?(Array) ? warnings : [],
            errors: normalize_errors(errors),
          }
        end

        def normalize_errors(errors)
          Array(errors).filter_map do |e|
            next unless e.is_a?(Hash)

            code = e.fetch(:code, nil)
            message = e.fetch(:message, nil)

            { code: code.to_s, message: message.to_s }
          end
        end

        def normalize_policy_error_mode(value)
          mode = value.to_s.strip.downcase.tr("-", "_")
          mode = "deny" if mode.empty?

          case mode
          when "deny"
            :deny
          when "allow"
            :allow
          when "raise"
            :raise
          else
            raise ArgumentError, "policy_error_mode must be :deny, :allow, or :raise"
          end
        end

        def evaluate_policy(name:, args:, tool_call_id:)
          policy = @policy
          return nil unless policy

          decision =
            begin
              policy.authorize_call(
                name: name,
                args: args,
                context: @policy_context,
                tool_call_id: tool_call_id,
              )
            rescue StandardError => e
              notify_policy_error(name: name, tool_call_id: tool_call_id, error_class: e.class.name, message: e.message.to_s)
              case @policy_error_mode
              when :allow
                return nil
              when :raise
                raise PolicyError, "tool policy raised: #{e.class}: #{e.message}"
              else
                return policy_error_envelope(name, reason_codes: ["POLICY_EXCEPTION"])
              end
            end

          decision = coerce_decision(decision)
          if decision.nil?
            notify_policy_error(
              name: name,
              tool_call_id: tool_call_id,
              error_class: "InvalidPolicyDecision",
              message: "tool policy returned an invalid decision",
            )
            case @policy_error_mode
            when :allow
              return nil
            when :raise
              raise PolicyError, "tool policy returned an invalid decision"
            else
              return policy_error_envelope(name, reason_codes: ["POLICY_INVALID_DECISION"])
            end
          end

          case decision.outcome
          when :allow
            nil
          when :deny
            policy_denied_envelope(name, decision)
          when :confirm
            policy_confirmation_required_envelope(name, decision)
          else
            notify_policy_error(
              name: name,
              tool_call_id: tool_call_id,
              error_class: "InvalidPolicyDecision",
              message: "tool policy returned an invalid decision",
            )
            policy_error_envelope(name, reason_codes: ["POLICY_INVALID_DECISION"])
          end
        end

        def notify_policy_error(name:, tool_call_id:, error_class:, message:)
          callback = @on_policy_error
          return unless callback&.respond_to?(:call)

          callback.call(
            {
              name: name.to_s,
              tool_call_id: tool_call_id.to_s,
              error_class: error_class.to_s,
              message: message.to_s,
            },
          )
        rescue StandardError
          nil
        end

        def coerce_decision(value)
          return value if value.is_a?(TavernKit::VibeTavern::ToolCalling::Policies::Decision)

          if value.is_a?(Hash)
            begin
              return TavernKit::VibeTavern::ToolCalling::Policies::Decision.new(
                outcome: value.fetch(:outcome, value.fetch("outcome", nil)),
                decision_id: value.fetch(:decision_id, value.fetch("decision_id", nil)),
                reason_codes: value.fetch(:reason_codes, value.fetch("reason_codes", nil)),
                message: value.fetch(:message, value.fetch("message", nil)),
                confirm: value.fetch(:confirm, value.fetch("confirm", nil)),
              )
            rescue StandardError
              return nil
            end
          end

          nil
        end

        def policy_denied_envelope(tool_name, decision)
          {
            ok: false,
            tool_name: tool_name.to_s,
            data: {
              policy: {
                outcome: "deny",
                decision_id: decision.decision_id,
                reason_codes: decision.reason_codes,
                message: decision.message,
              }.compact,
            },
            warnings: [],
            errors: [
              { code: "TOOL_POLICY_DENIED", message: "Tool denied by policy" },
            ],
          }
        end

        def policy_confirmation_required_envelope(tool_name, decision)
          policy_data = {
            outcome: "confirm",
            decision_id: decision.decision_id,
            reason_codes: decision.reason_codes,
            message: decision.message,
            confirm: decision.confirm,
          }.compact

          {
            ok: false,
            tool_name: tool_name.to_s,
            data: { policy: policy_data },
            warnings: [],
            errors: [
              { code: "TOOL_CONFIRMATION_REQUIRED", message: "Tool requires confirmation" },
            ],
          }
        end

        def policy_error_envelope(tool_name, reason_codes:)
          {
            ok: false,
            tool_name: tool_name.to_s,
            data: {
              policy: {
                outcome: "deny",
                decision_id: nil,
                reason_codes: Array(reason_codes).map { |v| v.to_s.strip }.reject(&:empty?).uniq,
                message: nil,
              },
            },
            warnings: [],
            errors: [
              { code: "TOOL_POLICY_ERROR", message: "Tool policy error" },
            ],
          }
        end
      end
    end
  end
end
