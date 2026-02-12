# frozen_string_literal: true

require_relative "../runner_config"
require_relative "../tools/mcp/snapshot"
require_relative "../tools/skills/config"
require_relative "../tools_builder/catalog"
require_relative "executor_router"
require_relative "executors/mcp_executor"
require_relative "executors/skills_executor"

module TavernKit
  module VibeTavern
    module ToolCalling
      module ExecutorBuilder
        module_function

        def build(runner_config:, registry:, default_executor: nil, mcp_snapshot: nil)
          raise ArgumentError, "runner_config is required" unless runner_config.is_a?(TavernKit::VibeTavern::RunnerConfig)
          raise ArgumentError, "registry is required" if registry.nil?
          unless registry.is_a?(TavernKit::VibeTavern::ToolsBuilder::Catalog)
            raise ArgumentError, "registry must be a ToolsBuilder::Catalog (got #{registry.class})"
          end

          cfg = runner_config.tool_calling
          return nil if cfg.tool_use_mode == :disabled

          max_bytes = cfg.max_tool_output_bytes

          tool_names = extract_tool_names(registry.openai_tools(expose: :model))

          needs_skills_executor = tool_names.any? { |name| name.start_with?("skills_") }
          needs_mcp_executor = tool_names.any? { |name| name.start_with?("mcp_") }
          needs_default_executor = tool_names.any? { |name| !name.start_with?("skills_") && !name.start_with?("mcp_") }

          skills_executor =
            if needs_skills_executor
              skills_cfg = TavernKit::VibeTavern::Tools::Skills::Config.from_context(runner_config.context)
              raise ArgumentError, "skills executor requires skills.enabled=true" unless skills_cfg.enabled

              Executors::SkillsExecutor.new(
                store: skills_cfg.store,
                max_bytes: max_bytes,
              )
            end

          mcp_executor =
            if needs_mcp_executor
              unless mcp_snapshot.is_a?(TavernKit::VibeTavern::Tools::MCP::Snapshot)
                raise ArgumentError, "mcp_snapshot is required for mcp_* tools"
              end

              Executors::McpExecutor.new(
                clients: mcp_snapshot.clients,
                mapping: mcp_snapshot.mapping,
                max_bytes: max_bytes,
              )
            end

          if needs_default_executor && default_executor.nil?
            raise ArgumentError, "default_executor is required for non-prefixed tools"
          end

          if skills_executor.nil? && mcp_executor.nil? && default_executor.nil?
            raise ArgumentError, "at least one tool executor is required when tool_use_mode is enabled"
          end

          ExecutorRouter.new(
            skills_executor: skills_executor,
            mcp_executor: mcp_executor,
            default_executor: default_executor,
          )
        end

        def extract_tool_names(tools)
          Array(tools).filter_map do |tool|
            next unless tool.is_a?(Hash)

            fn = tool.fetch(:function, nil)
            fn = tool.fetch("function", nil) unless fn.is_a?(Hash)
            next unless fn.is_a?(Hash)

            name = fn.fetch(:name, fn.fetch("name", nil)).to_s.strip
            next if name.empty?

            name
          end
        end
        private_class_method :extract_tool_names
      end
    end
  end
end
