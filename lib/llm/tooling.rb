# frozen_string_literal: true

require "agent_core"

module LLM
  module Tooling
    def self.registry(tooling_key:, context_attributes: {})
      key = normalize_tooling_key(tooling_key)
      _ctx = normalize_context_attributes(context_attributes)

      case key
      when "default"
        AgentCore::Resources::Tools::Registry.new.register_many(default_tools)
      else
        raise ArgumentError, "unknown tooling_key: #{key.inspect}"
      end
    end

    def self.policy(tooling_key:, context_attributes: {})
      key = normalize_tooling_key(tooling_key)
      _ctx = normalize_context_attributes(context_attributes)

      case key
      when "default"
        AgentCore::Resources::Tools::Policy::AllowAll.new
      else
        raise ArgumentError, "unknown tooling_key: #{key.inspect}"
      end
    end

    def self.default_tools
      [
        AgentCore::Resources::Tools::Tool.new(
          name: "echo",
          description: "Echo input text back to the caller.",
          parameters: {
            type: "object",
            properties: {
              text: { type: "string", description: "Text to echo back." },
            },
            required: ["text"],
          },
        ) do |arguments, context:|
          text = arguments.fetch("text").to_s
          AgentCore::Resources::Tools::ToolResult.success(text: text, metadata: { duration_ms: 0.0 })
        end,
        AgentCore::Resources::Tools::Tool.new(
          name: "noop",
          description: "No-op tool (returns ok).",
          parameters: { type: "object", properties: {} },
        ) do |_arguments, context:|
          AgentCore::Resources::Tools::ToolResult.success(text: "ok", metadata: { duration_ms: 0.0 })
        end,
      ]
    end
    private_class_method :default_tools

    def self.normalize_tooling_key(value)
      key = value.to_s.strip
      key = "default" if key.empty?
      key
    end
    private_class_method :normalize_tooling_key

    def self.normalize_context_attributes(value)
      case value
      when nil
        {}
      when Hash
        AgentCore::Utils.deep_symbolize_keys(value)
      else
        raise ArgumentError, "context_attributes must be a Hash"
      end
    end
    private_class_method :normalize_context_attributes
  end
end
