# frozen_string_literal: true

require "json"
require "time"

module AgentCore
  module PromptRunner
    # JSON-safe serializer/deserializer for pending tool execution tasks.
    #
    # Intended for app-side schedulers (ActiveJob/MQ/worker processes) that need
    # a stable payload for executing deferred tools.
    module ToolTaskCodec
      SCHEMA_VERSION = 1

      ToolTaskBatch =
        Data.define(
          :run_id,
          :turn_number,
          :tasks,
          :context_attributes,
          :max_tool_output_bytes,
        )

      def self.dump(continuation, context_keys: [])
        cont = coerce_continuation(continuation)

        unless cont.pause_reason == :awaiting_tool_results
          raise ArgumentError, "continuation pause_reason is #{cont.pause_reason.inspect} (expected :awaiting_tool_results)"
        end

        pending = Array(cont.pending_tool_executions)
        if pending.empty?
          raise ArgumentError, "continuation has no pending tool executions"
        end

        context_keys = normalize_context_keys(context_keys)
        context_attributes = cont.context_attributes
        context_attributes = context_attributes.is_a?(Hash) ? context_attributes : {}

        payload = {
          "schema_version" => SCHEMA_VERSION,
          "run_id" => cont.run_id.to_s,
          "turn_number" => Integer(cont.turn),
          "tasks" => serialize_tasks(pending),
          "context_attributes" => serialize_context_attributes(context_attributes, context_keys: context_keys),
          "max_tool_output_bytes" => Integer(cont.max_tool_output_bytes),
        }

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
              raise ArgumentError, "tool task payload is not valid JSON: #{e.message}"
            end
          when Hash
            payload
          else
            raise ArgumentError, "tool task payload must be a Hash or JSON String (got #{payload.class})"
          end

        raise ArgumentError, "tool task payload must be a Hash" unless h.is_a?(Hash)

        schema_version = Integer(fetch_required(h, "schema_version", path: "schema_version"))
        unless schema_version == SCHEMA_VERSION
          raise ArgumentError, "unsupported tool task schema_version=#{schema_version} (supported: #{SCHEMA_VERSION})"
        end

        run_id = fetch_required(h, "run_id", path: "run_id").to_s
        raise ArgumentError, "run_id is required" if run_id.strip.empty?

        turn_number = Integer(fetch_required(h, "turn_number", path: "turn_number"))
        tasks_raw = fetch_required(h, "tasks", path: "tasks")
        tasks = deserialize_tasks(tasks_raw)

        context_attributes_raw = h.fetch("context_attributes", {})
        context_attributes = deep_symbolize_hash(context_attributes_raw, path: "context_attributes")

        max_tool_output_bytes = Integer(fetch_required(h, "max_tool_output_bytes", path: "max_tool_output_bytes"))

        ToolTaskBatch.new(
          run_id: run_id.freeze,
          turn_number: turn_number,
          tasks: tasks.freeze,
          context_attributes: context_attributes.freeze,
          max_tool_output_bytes: max_tool_output_bytes,
        )
      end

      def self.coerce_continuation(value)
        return value if value.is_a?(AgentCore::PromptRunner::Continuation)

        AgentCore::PromptRunner::ContinuationCodec.load(value)
      end
      private_class_method :coerce_continuation

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

      def self.serialize_tasks(pending_tool_executions)
        pending_tool_executions.map.with_index do |pending, idx|
          unless pending.respond_to?(:tool_call_id) &&
                 pending.respond_to?(:name) &&
                 pending.respond_to?(:executed_name) &&
                 pending.respond_to?(:arguments) &&
                 pending.respond_to?(:arguments_summary) &&
                 pending.respond_to?(:source)
            raise ArgumentError, "tasks[#{idx}] must be a PendingToolExecution"
          end

          args = pending.arguments
          raise ArgumentError, "tasks[#{idx}].arguments must be a Hash" unless args.is_a?(Hash)

          {
            "tool_call_id" => pending.tool_call_id.to_s,
            "name" => pending.name.to_s,
            "executed_name" => pending.executed_name.to_s,
            "arguments" => json_safe(AgentCore::Utils.deep_stringify_keys(args)),
            "arguments_summary" => pending.arguments_summary.nil? ? nil : pending.arguments_summary.to_s,
            "source" => pending.source.nil? ? nil : pending.source.to_s,
          }
        end
      end
      private_class_method :serialize_tasks

      def self.deserialize_tasks(value)
        raw = Array(value)
        raw.map.with_index do |h, idx|
          unless h.is_a?(Hash)
            raise ArgumentError, "tasks[#{idx}] must be a Hash"
          end

          tool_call_id = fetch_required(h, "tool_call_id", path: "tasks[#{idx}].tool_call_id").to_s
          name = fetch_required(h, "name", path: "tasks[#{idx}].name").to_s
          executed_name = fetch_required(h, "executed_name", path: "tasks[#{idx}].executed_name").to_s
          arguments = fetch_required(h, "arguments", path: "tasks[#{idx}].arguments")
          raise ArgumentError, "tasks[#{idx}].arguments must be a Hash" unless arguments.is_a?(Hash)

          arguments = AgentCore::Utils.deep_stringify_keys(arguments)

          arguments_summary = h.fetch("arguments_summary", h.fetch(:arguments_summary, nil))
          source = h.fetch("source", h.fetch(:source, nil))

          AgentCore::PromptRunner::PendingToolExecution.new(
            tool_call_id: tool_call_id,
            name: name,
            executed_name: executed_name,
            arguments: arguments,
            arguments_summary: arguments_summary.nil? ? nil : arguments_summary.to_s,
            source: source.nil? ? nil : source.to_s,
          )
        end
      rescue StandardError => e
        raise ArgumentError, "failed to deserialize tasks: #{e.message}"
      end
      private_class_method :deserialize_tasks

      def self.fetch_required(hash, key, path:)
        k = key.to_s
        return hash[k] if hash.key?(k)
        return hash[key.to_sym] if hash.key?(key.to_sym)

        raise ArgumentError, "tool task payload missing #{path}"
      end
      private_class_method :fetch_required

      def self.deep_symbolize_hash(value, path:)
        raise ArgumentError, "#{path} must be a Hash" unless value.is_a?(Hash)

        AgentCore::Utils.deep_symbolize_keys(value)
      end
      private_class_method :deep_symbolize_hash

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
      rescue StandardError
        AgentCore::Utils.truncate_utf8_bytes(value.to_s, max_bytes: 2_000)
      end
      private_class_method :json_safe
    end
  end
end
