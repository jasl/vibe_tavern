# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolsBuilder
      module Builder
        module_function

        def build(
          runner_config:,
          base_catalog: nil,
          default_executor: nil,
          mcp_definitions: nil,
          mcp_executor: nil
        )
          raise ArgumentError, "runner_config is required" unless runner_config.is_a?(TavernKit::VibeTavern::RunnerConfig)

          cfg = runner_config.tool_calling
          tools_enabled = cfg.tool_use_enabled?

          base_catalog ||= TavernKit::VibeTavern::Tools::Custom::Catalog.new
          unless base_catalog.is_a?(TavernKit::VibeTavern::ToolsBuilder::Catalog)
            raise ArgumentError, "base_catalog must be a ToolsBuilder::Catalog (got #{base_catalog.class})"
          end

          skills_cfg = TavernKit::VibeTavern::Tools::Skills::Config.from_context(runner_config.context)

          custom_tools = Array(base_catalog.definitions)
          skill_tools = skills_cfg.enabled ? TavernKit::VibeTavern::Tools::Skills::ToolExecutor.tool_definitions : []
          mcp_tools = mcp_definitions.nil? ? [] : Array(mcp_definitions)

          normalized_defs = normalize_definitions(custom_tools + skill_tools + mcp_tools)
          normalized_defs.sort_by!(&:name)

          base_custom_catalog = TavernKit::VibeTavern::Tools::Custom::Catalog.new(definitions: normalized_defs)

          catalog =
            if cfg.tool_allowlist || cfg.tool_denylist
              TavernKit::VibeTavern::ToolsBuilder::FilteredCatalog.new(
                base: base_custom_catalog,
                allow: cfg.tool_allowlist,
                deny: cfg.tool_denylist,
              )
            else
              base_custom_catalog
            end

          visible_defs = catalog.definitions.select(&:exposed_to_model?)

          if tools_enabled
            catalog =
              TavernKit::VibeTavern::ToolsBuilder::CatalogSnapshot.build_from(
                base_catalog: catalog,
                max_count: cfg.max_tool_definitions_count,
                max_bytes: cfg.max_tool_definitions_bytes,
              )
          end

          executor =
            if tools_enabled
              if !mcp_definitions.nil? && mcp_executor.nil?
                raise ArgumentError, "mcp_executor is required when mcp_definitions are provided"
              end

              skills_executor =
                if skills_cfg.enabled
                  TavernKit::VibeTavern::Tools::Skills::ToolExecutor.new(
                    store: skills_cfg.store,
                    max_bytes: cfg.max_tool_output_bytes,
                  )
                end

              if visible_defs.any? { |d| d.name.to_s.start_with?("skills_") } && skills_executor.nil?
                raise ArgumentError, "skills executor is required for skills_* tools"
              end

              if visible_defs.any? { |d| d.name.to_s.start_with?("mcp_") } && mcp_executor.nil?
                raise ArgumentError, "mcp_executor is required for mcp_* tools"
              end

              needs_default_executor =
                visible_defs.any? do |d|
                  n = d.name.to_s
                  !n.start_with?("skills_") && !n.start_with?("mcp_")
                end

              needs_default_executor = false if visible_defs.empty?

              if needs_default_executor && default_executor.nil?
                raise ArgumentError, "default_executor is required for non-prefixed tools"
              end

              if skills_executor.nil? && mcp_executor.nil? && default_executor.nil?
                raise ArgumentError, "at least one tool executor is required when tool_use_mode is enabled"
              end

              TavernKit::VibeTavern::ToolsBuilder::ExecutorRouter.new(
                skills_executor: skills_executor,
                mcp_executor: mcp_executor,
                default_executor: default_executor,
              )
            end

          BuildResult.new(catalog: catalog, executor: executor)
        end

        def normalize_definitions(defs)
          normalized = TavernKit::VibeTavern::Tools::Custom::Catalog.new(definitions: defs).definitions

          dupes =
            normalized
              .group_by(&:name)
              .select { |_name, group| group.size > 1 }
              .keys
              .sort

          if dupes.any?
            preview = dupes.first(10)
            suffix = dupes.size > preview.size ? ", ..." : ""
            raise ArgumentError, "duplicate tool names: #{preview.join(", ")}#{suffix}"
          end

          normalized
        end
        private_class_method :normalize_definitions
      end
    end
  end
end
