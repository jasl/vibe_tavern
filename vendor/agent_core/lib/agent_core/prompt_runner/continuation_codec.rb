# frozen_string_literal: true

require "json"
require "time"

module AgentCore
  module PromptRunner
    # JSON-safe serializer/deserializer for PromptRunner continuations.
    #
    # Continuations are intended to be treated as opaque by downstream apps.
    # This codec provides a versioned, JSON-friendly representation so apps can
    # persist pause/resume state across process boundaries safely.
    module ContinuationCodec
      SCHEMA_VERSION = 1

      def self.dump(continuation, context_keys: [], include_traces: true)
        unless continuation.is_a?(AgentCore::PromptRunner::Continuation)
          raise ArgumentError, "continuation must be a PromptRunner::Continuation (got #{continuation.class})"
        end

        context_keys = normalize_context_keys(context_keys)
        context_attributes = continuation.context_attributes
        context_attributes = context_attributes.is_a?(Hash) ? context_attributes : {}

        payload = {
          "schema_version" => SCHEMA_VERSION,
          "run_id" => continuation.run_id.to_s,
          "started_at" => iso8601_utc(continuation.started_at),
          "duration_ms" => continuation.duration_ms.to_f,
          "turn" => Integer(continuation.turn),
          "max_turns" => Integer(continuation.max_turns),
          "messages" => serialize_messages(Array(continuation.messages)),
          "model" => continuation.model.to_s,
          "options" => json_safe_hash(continuation.options),
          "tools" => json_safe_array(continuation.tools),
          "tools_enabled" => continuation.tools_enabled == true,
          "empty_final_fixup_attempted" => continuation.empty_final_fixup_attempted == true,
          "any_tool_calls_seen" => continuation.any_tool_calls_seen == true,
          "tool_calls_record" => json_safe_array(continuation.tool_calls_record),
          "aggregated_usage" => serialize_usage(continuation.aggregated_usage),
          "per_turn_usage" => serialize_usage_list(continuation.per_turn_usage),
          "pause_reason" => continuation.pause_reason.to_s,
          "pending_tool_calls" => serialize_tool_calls(Array(continuation.pending_tool_calls)),
          "pending_tool_executions" => json_safe_array(continuation.pending_tool_executions),
          "buffered_tool_results" => serialize_buffered_tool_results(continuation.buffered_tool_results),
          "pending_decisions" => serialize_pending_decisions(continuation.pending_decisions),
          "context_attributes" => serialize_context_attributes(context_attributes, context_keys: context_keys),
          "max_tool_output_bytes" => Integer(continuation.max_tool_output_bytes),
          "max_tool_calls_per_turn" => continuation.max_tool_calls_per_turn.nil? ? nil : Integer(continuation.max_tool_calls_per_turn),
          "fix_empty_final" => continuation.fix_empty_final == true,
          "fix_empty_final_user_text" => continuation.fix_empty_final_user_text.to_s,
          "fix_empty_final_disable_tools" => continuation.fix_empty_final_disable_tools == true,
        }

        if include_traces
          payload["turn_traces"] = json_safe_array(serialize_turn_traces(Array(continuation.turn_traces)))
        end

        payload.delete("buffered_tool_results") if payload.fetch("buffered_tool_results").empty?

        JSON.generate(payload)
        payload
      end

      def self.load(payload)
        h =
          case payload
          when String
            begin
              JSON.parse(payload)
            rescue JSON::ParserError => e
              raise ArgumentError, "continuation payload is not valid JSON: #{e.message}"
            end
          when Hash
            payload
          else
            raise ArgumentError, "continuation payload must be a Hash or JSON String (got #{payload.class})"
          end

        raise ArgumentError, "continuation payload must be a Hash" unless h.is_a?(Hash)

        schema_version = Integer(fetch_required(h, "schema_version", path: "schema_version"))
        unless schema_version == SCHEMA_VERSION
          raise ArgumentError, "unsupported continuation schema_version=#{schema_version} (supported: #{SCHEMA_VERSION})"
        end

        run_id = fetch_required(h, "run_id", path: "run_id").to_s
        raise ArgumentError, "run_id is required" if run_id.strip.empty?

        started_at = parse_time_utc(fetch_required(h, "started_at", path: "started_at").to_s)
        duration_ms = Float(fetch_required(h, "duration_ms", path: "duration_ms"))
        turn = Integer(fetch_required(h, "turn", path: "turn"))
        max_turns = Integer(fetch_required(h, "max_turns", path: "max_turns"))

        messages_raw = fetch_required(h, "messages", path: "messages")
        messages = deserialize_messages(messages_raw)

        model = fetch_required(h, "model", path: "model").to_s

        options_raw = fetch_required(h, "options", path: "options")
        options = deep_symbolize_hash(options_raw, path: "options")

        tools_raw = fetch_required(h, "tools", path: "tools")
        tools = deep_stringify_hash_or_array(tools_raw, path: "tools")

        tools_enabled = !!fetch_required(h, "tools_enabled", path: "tools_enabled")
        empty_final_fixup_attempted = !!fetch_required(h, "empty_final_fixup_attempted", path: "empty_final_fixup_attempted")
        any_tool_calls_seen = !!fetch_required(h, "any_tool_calls_seen", path: "any_tool_calls_seen")

        tool_calls_record_raw = fetch_required(h, "tool_calls_record", path: "tool_calls_record")
        tool_calls_record = deep_symbolize_hash_or_array(tool_calls_record_raw, path: "tool_calls_record")

        aggregated_usage = deserialize_usage(h.fetch("aggregated_usage", nil))
        per_turn_usage = deserialize_usage_list(h.fetch("per_turn_usage", []))

        turn_traces_raw = h.fetch("turn_traces", [])
        turn_traces = deserialize_turn_traces(turn_traces_raw)

        pause_reason = fetch_required(h, "pause_reason", path: "pause_reason").to_s
        pause_reason = pause_reason.strip
        unless %w[awaiting_tool_confirmation awaiting_tool_results].include?(pause_reason)
          raise ArgumentError, "pause_reason must be awaiting_tool_confirmation or awaiting_tool_results (got #{pause_reason.inspect})"
        end

        pending_tool_calls_raw = fetch_required(h, "pending_tool_calls", path: "pending_tool_calls")
        pending_tool_calls = deserialize_tool_calls(pending_tool_calls_raw)

        pending_tool_executions_raw = h.fetch("pending_tool_executions", [])
        pending_tool_executions = deserialize_pending_tool_executions(pending_tool_executions_raw)

        buffered_tool_results_raw = h.fetch("buffered_tool_results", {})
        buffered_tool_results = deserialize_buffered_tool_results(buffered_tool_results_raw)

        pending_decisions_raw = fetch_required(h, "pending_decisions", path: "pending_decisions")
        pending_decisions = deserialize_pending_decisions(pending_decisions_raw)

        context_attributes_raw = h.fetch("context_attributes", {})
        context_attributes = deep_symbolize_hash(context_attributes_raw, path: "context_attributes")

        max_tool_output_bytes = Integer(fetch_required(h, "max_tool_output_bytes", path: "max_tool_output_bytes"))
        max_tool_calls_per_turn =
          h.key?("max_tool_calls_per_turn") && !h.fetch("max_tool_calls_per_turn").nil? ? Integer(h.fetch("max_tool_calls_per_turn")) : nil

        fix_empty_final = !!fetch_required(h, "fix_empty_final", path: "fix_empty_final")
        fix_empty_final_user_text = fetch_required(h, "fix_empty_final_user_text", path: "fix_empty_final_user_text").to_s
        fix_empty_final_disable_tools = !!fetch_required(h, "fix_empty_final_disable_tools", path: "fix_empty_final_disable_tools")

        AgentCore::PromptRunner::Continuation.new(
          run_id: run_id,
          started_at: started_at,
          duration_ms: duration_ms,
          turn: turn,
          max_turns: max_turns,
          messages: messages.freeze,
          model: model,
          options: options.freeze,
          tools: tools.freeze,
          tools_enabled: tools_enabled,
          empty_final_fixup_attempted: empty_final_fixup_attempted,
          any_tool_calls_seen: any_tool_calls_seen,
          tool_calls_record: tool_calls_record.freeze,
          aggregated_usage: aggregated_usage,
          per_turn_usage: per_turn_usage.freeze,
          turn_traces: turn_traces.freeze,
          pause_reason: pause_reason.to_sym,
          pending_tool_calls: pending_tool_calls.freeze,
          pending_tool_executions: pending_tool_executions.freeze,
          buffered_tool_results: buffered_tool_results.freeze,
          pending_decisions: pending_decisions.freeze,
          context_attributes: context_attributes.freeze,
          max_tool_output_bytes: max_tool_output_bytes,
          max_tool_calls_per_turn: max_tool_calls_per_turn,
          fix_empty_final: fix_empty_final,
          fix_empty_final_user_text: fix_empty_final_user_text,
          fix_empty_final_disable_tools: fix_empty_final_disable_tools,
        )
      end

      def self.normalize_context_keys(value)
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
      private_class_method :normalize_context_keys

      def self.serialize_context_attributes(attributes, context_keys:)
        return {} if context_keys.empty?

        context_keys.each_with_object({}) do |key, out|
          next unless attributes.key?(key)

          out[key.to_s] = AgentCore::Utils.truncate_utf8_bytes(attributes.fetch(key).to_s, max_bytes: 200)
        end
      rescue StandardError
        {}
      end
      private_class_method :serialize_context_attributes

      def self.serialize_messages(messages)
        messages.map do |m|
          unless m.is_a?(AgentCore::Message)
            raise ArgumentError, "messages must be AgentCore::Message objects"
          end

          json_safe_hash(m.to_h)
        end
      end
      private_class_method :serialize_messages

      def self.deserialize_messages(value)
        raw = Array(value)
        raw.map do |h|
          unless h.is_a?(Hash)
            raise ArgumentError, "messages must be an Array of Hash"
          end

          AgentCore::Message.from_h(AgentCore::Utils.deep_symbolize_keys(h))
        end
      rescue StandardError => e
        raise ArgumentError, "failed to deserialize messages: #{e.message}"
      end
      private_class_method :deserialize_messages

      def self.serialize_tool_calls(tool_calls)
        tool_calls.map do |tc|
          unless tc.is_a?(AgentCore::ToolCall)
            raise ArgumentError, "pending_tool_calls must be AgentCore::ToolCall objects"
          end

          json_safe_hash(tc.to_h)
        end
      end
      private_class_method :serialize_tool_calls

      def self.deserialize_tool_calls(value)
        raw = Array(value)
        raw.map do |h|
          unless h.is_a?(Hash)
            raise ArgumentError, "pending_tool_calls must be an Array of Hash"
          end

          AgentCore::ToolCall.from_h(AgentCore::Utils.deep_symbolize_keys(h))
        end
      rescue StandardError => e
        raise ArgumentError, "failed to deserialize pending_tool_calls: #{e.message}"
      end
      private_class_method :deserialize_tool_calls

      def self.serialize_usage(value)
        return nil if value.nil?
        return json_safe_hash(value.to_h) if value.respond_to?(:to_h)

        nil
      rescue StandardError
        nil
      end
      private_class_method :serialize_usage

      def self.serialize_usage_list(value)
        Array(value).filter_map do |u|
          serialize_usage(u)
        end
      end
      private_class_method :serialize_usage_list

      def self.deserialize_usage(value)
        return nil if value.nil?
        return value if value.is_a?(AgentCore::Resources::Provider::Usage)
        raise ArgumentError, "usage must be a Hash" unless value.is_a?(Hash)

        h = AgentCore::Utils.deep_symbolize_keys(value)

        AgentCore::Resources::Provider::Usage.new(
          input_tokens: Integer(h.fetch(:input_tokens, 0)),
          output_tokens: Integer(h.fetch(:output_tokens, 0)),
          cache_creation_tokens: Integer(h.fetch(:cache_creation_tokens, 0)),
          cache_read_tokens: Integer(h.fetch(:cache_read_tokens, 0)),
        )
      rescue StandardError => e
        raise ArgumentError, "failed to deserialize usage: #{e.message}"
      end
      private_class_method :deserialize_usage

      def self.deserialize_usage_list(value)
        Array(value).map { |v| deserialize_usage(v) }
      rescue StandardError => e
        raise ArgumentError, "failed to deserialize per_turn_usage: #{e.message}"
      end
      private_class_method :deserialize_usage_list

      def self.serialize_turn_traces(traces)
        traces.map do |tt|
          h = tt.respond_to?(:to_h) ? tt.to_h : tt
          json_safe_hash(h)
        end
      end
      private_class_method :serialize_turn_traces

      def self.deserialize_turn_traces(value)
        raw = value.nil? ? [] : value
        raw = [] if raw == ""
        arr = Array(raw)

        arr.map do |h|
          next unless h.is_a?(Hash)

          sym = AgentCore::Utils.deep_symbolize_keys(h)
          sym = normalize_turn_trace_times(sym)

          build_turn_trace(sym)
        end.compact
      rescue StandardError => e
        raise ArgumentError, "failed to deserialize turn_traces: #{e.message}"
      end
      private_class_method :deserialize_turn_traces

      def self.normalize_turn_trace_times(sym_hash)
        h = sym_hash.is_a?(Hash) ? sym_hash.dup : {}

        if h[:started_at]
          h[:started_at] = parse_time_utc(h[:started_at].to_s)
        end

        if h[:ended_at]
          h[:ended_at] = parse_time_utc(h[:ended_at].to_s)
        end

        h
      end
      private_class_method :normalize_turn_trace_times

      def self.build_turn_trace(sym)
        llm = sym.fetch(:llm, nil)
        llm_obj = llm.is_a?(Hash) ? build_llm_trace(llm) : nil

        tool_auth = Array(sym.fetch(:tool_authorizations, [])).filter_map { |t| build_tool_authorization_trace(t) }
        tool_exec = Array(sym.fetch(:tool_executions, [])).filter_map { |t| build_tool_execution_trace(t) }

        AgentCore::PromptRunner::TurnTrace.new(
          turn_number: Integer(sym.fetch(:turn_number)),
          started_at: sym.fetch(:started_at),
          ended_at: sym.fetch(:ended_at),
          duration_ms: sym.fetch(:duration_ms, nil),
          llm: llm_obj,
          tool_authorizations: tool_auth,
          tool_executions: tool_exec,
          stop_reason: sym.fetch(:stop_reason, nil),
          usage: sym.fetch(:usage, nil),
        )
      rescue StandardError
        nil
      end
      private_class_method :build_turn_trace

      def self.build_llm_trace(hash)
        h = AgentCore::Utils.deep_symbolize_keys(hash)

        AgentCore::PromptRunner::LlmCallTrace.new(
          model: h.fetch(:model, "").to_s,
          messages_count: Integer(h.fetch(:messages_count, 0)),
          tools_count: Integer(h.fetch(:tools_count, 0)),
          options_summary: h.fetch(:options_summary, nil),
          stop_reason: h.fetch(:stop_reason, nil),
          usage: h.fetch(:usage, nil),
          duration_ms: h.fetch(:duration_ms, nil),
        )
      rescue StandardError
        nil
      end
      private_class_method :build_llm_trace

      def self.build_tool_authorization_trace(hash)
        h = AgentCore::Utils.deep_symbolize_keys(hash.is_a?(Hash) ? hash : {})

        AgentCore::PromptRunner::ToolAuthorizationTrace.new(
          tool_call_id: h.fetch(:tool_call_id, "").to_s,
          name: h.fetch(:name, "").to_s,
          outcome: h.fetch(:outcome, nil),
          reason: h.fetch(:reason, nil),
          duration_ms: h.fetch(:duration_ms, nil),
        )
      rescue StandardError
        nil
      end
      private_class_method :build_tool_authorization_trace

      def self.build_tool_execution_trace(hash)
        h = AgentCore::Utils.deep_symbolize_keys(hash.is_a?(Hash) ? hash : {})

        AgentCore::PromptRunner::ToolExecutionTrace.new(
          tool_call_id: h.fetch(:tool_call_id, "").to_s,
          name: h.fetch(:name, "").to_s,
          executed_name: h.fetch(:executed_name, "").to_s,
          source: h.fetch(:source, "").to_s,
          arguments_summary: h.fetch(:arguments_summary, nil),
          result_summary: h.fetch(:result_summary, nil),
          error: h.fetch(:error, nil),
          duration_ms: h.fetch(:duration_ms, nil),
        )
      rescue StandardError
        nil
      end
      private_class_method :build_tool_execution_trace

      def self.serialize_pending_decisions(value)
        raw = value.is_a?(Hash) ? value : {}

        raw.each_with_object({}) do |(k, v), out|
          id = k.to_s
          next if id.strip.empty?

          if v.respond_to?(:outcome) && v.respond_to?(:reason)
            out[id] = { "outcome" => v.outcome.to_s, "reason" => v.reason.nil? ? nil : v.reason.to_s }
          elsif v.is_a?(Hash)
            vv = json_safe_hash(v)
            out[id] = { "outcome" => vv.fetch("outcome", "").to_s, "reason" => vv.fetch("reason", nil)&.to_s }
          end
        end
      rescue StandardError
        {}
      end
      private_class_method :serialize_pending_decisions

      def self.deserialize_pending_decisions(value)
        raw = value.is_a?(Hash) ? value : {}

        raw.each_with_object({}) do |(k, v), out|
          id = k.to_s
          next if id.strip.empty?
          next unless v.is_a?(Hash)

          outcome = v.fetch("outcome", v.fetch(:outcome, nil)).to_s.strip
          reason = v.fetch("reason", v.fetch(:reason, nil))
          reason = nil if reason.nil? || reason.to_s.strip.empty?

          decision =
            case outcome
            when "allow"
              AgentCore::Resources::Tools::Policy::Decision.allow(reason: reason)
            when "deny"
              AgentCore::Resources::Tools::Policy::Decision.deny(reason: reason || "denied")
            when "confirm"
              AgentCore::Resources::Tools::Policy::Decision.confirm(reason: reason || "confirmation required")
            else
              nil
            end

          out[id] = decision if decision
        end
      rescue StandardError => e
        raise ArgumentError, "failed to deserialize pending_decisions: #{e.message}"
      end
      private_class_method :deserialize_pending_decisions

      def self.deserialize_pending_tool_executions(value)
        raw = Array(value)
        raw.map do |h|
          unless h.is_a?(Hash)
            raise ArgumentError, "pending_tool_executions must be an Array of Hash"
          end

          sym = AgentCore::Utils.deep_symbolize_keys(h)

          args = sym.fetch(:arguments, {})
          unless args.is_a?(Hash)
            raise ArgumentError, "pending_tool_executions.arguments must be a Hash"
          end

          AgentCore::PromptRunner::PendingToolExecution.new(
            tool_call_id: sym.fetch(:tool_call_id, "").to_s,
            name: sym.fetch(:name, "").to_s,
            executed_name: sym.fetch(:executed_name, "").to_s,
            arguments: AgentCore::Utils.deep_stringify_keys(args),
            arguments_summary: sym.fetch(:arguments_summary, nil),
            source: sym.fetch(:source, nil),
          )
        end
      rescue StandardError => e
        raise ArgumentError, "failed to deserialize pending_tool_executions: #{e.message}"
      end
      private_class_method :deserialize_pending_tool_executions

      def self.serialize_buffered_tool_results(value)
        h = value.is_a?(Hash) ? value : {}
        return {} if h.empty?

        h.each_with_object({}) do |(tool_call_id, result), out|
          id = tool_call_id.to_s
          next if id.strip.empty?
          next unless result.is_a?(AgentCore::Resources::Tools::ToolResult)

          out[id] = json_safe_hash(result.to_h)
        end
      rescue StandardError
        {}
      end
      private_class_method :serialize_buffered_tool_results

      def self.deserialize_buffered_tool_results(value)
        return {} if value.nil?
        raise ArgumentError, "buffered_tool_results must be a Hash" unless value.is_a?(Hash)

        value.each_with_object({}) do |(tool_call_id, raw), out|
          id = tool_call_id.to_s
          next if id.strip.empty?

          unless raw.is_a?(Hash)
            raise ArgumentError, "buffered_tool_results[#{id.inspect}] must be a Hash"
          end

          content = fetch_required(raw, "content", path: "buffered_tool_results[#{id.inspect}].content")
          error = fetch_required(raw, "error", path: "buffered_tool_results[#{id.inspect}].error")
          metadata = fetch_required(raw, "metadata", path: "buffered_tool_results[#{id.inspect}].metadata")

          raise ArgumentError, "buffered_tool_results[#{id.inspect}].content must be an Array" unless content.is_a?(Array)
          raise ArgumentError, "buffered_tool_results[#{id.inspect}].metadata must be a Hash" unless metadata.is_a?(Hash)

          metadata = AgentCore::Utils.symbolize_keys(metadata)

          out[id] =
            AgentCore::Resources::Tools::ToolResult.new(
              content: content,
              error: !!error,
              metadata: metadata
            )
        end
      rescue StandardError => e
        raise ArgumentError, "failed to deserialize buffered_tool_results: #{e.message}"
      end
      private_class_method :deserialize_buffered_tool_results

      def self.iso8601_utc(time)
        t = time.is_a?(Time) ? time : Time.parse(time.to_s)
        t.utc.iso8601(6)
      rescue StandardError => e
        raise ArgumentError, "invalid time: #{e.message}"
      end
      private_class_method :iso8601_utc

      def self.parse_time_utc(value)
        t = Time.parse(value.to_s).utc
        Time.utc(t.year, t.month, t.day, t.hour, t.min, t.sec, t.usec)
      rescue StandardError => e
        raise ArgumentError, "invalid time: #{e.message}"
      end
      private_class_method :parse_time_utc

      def self.json_safe_hash(value)
        value = value.respond_to?(:to_h) ? value.to_h : value
        h = value.is_a?(Hash) ? value : {}
        json_safe(h)
      end
      private_class_method :json_safe_hash

      def self.json_safe_array(value)
        json_safe(Array(value))
      end
      private_class_method :json_safe_array

      def self.json_safe(value)
        case value
        when nil, true, false, Integer, Float, String
          value
        when Numeric
          value.to_f
        when Symbol
          value.to_s
        when Time
          value.utc.iso8601(6)
        when Data
          json_safe(value.to_h)
        when Array
          value.map { |v| json_safe(v) }
        when Hash
          value.each_with_object({}) do |(k, v), out|
            out[k.to_s] = json_safe(v)
          end
        else
          AgentCore::Utils.truncate_utf8_bytes(value.to_s, max_bytes: 2_000)
        end
      end
      private_class_method :json_safe

      def self.fetch_required(hash, key, path:)
        k = key.to_s
        return hash[k] if hash.key?(k)
        return hash[key.to_sym] if hash.key?(key.to_sym)

        raise ArgumentError, "continuation payload missing #{path}"
      end
      private_class_method :fetch_required

      def self.deep_symbolize_hash(value, path:)
        raise ArgumentError, "#{path} must be a Hash" unless value.is_a?(Hash)

        AgentCore::Utils.deep_symbolize_keys(value)
      end
      private_class_method :deep_symbolize_hash

      def self.deep_symbolize_hash_or_array(value, path:)
        case value
        when Hash
          AgentCore::Utils.deep_symbolize_keys(value)
        when Array
          value.map { |v| deep_symbolize_hash_or_array(v, path: path) }
        else
          raise ArgumentError, "#{path} must be a Hash or Array"
        end
      end
      private_class_method :deep_symbolize_hash_or_array

      def self.deep_stringify_hash_or_array(value, path:)
        case value
        when Hash
          AgentCore::Utils.deep_stringify_keys(value)
        when Array
          value.map { |v| deep_stringify_hash_or_array(v, path: path) }
        else
          raise ArgumentError, "#{path} must be a Hash or Array"
        end
      end
      private_class_method :deep_stringify_hash_or_array
    end
  end
end
