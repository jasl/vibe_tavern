# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolsBuilder
      module Builder
        module_function

        def build(
          runner_config:,
          base_catalog: nil,
          mcp_definitions: nil
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
          skill_tools = skills_cfg.enabled ? TavernKit::VibeTavern::Tools::Skills::ToolDefinitions.definitions : []
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

          if tools_enabled
            catalog =
              TavernKit::VibeTavern::ToolsBuilder::CatalogSnapshot.build_from(
                base_catalog: catalog,
                max_count: cfg.max_tool_definitions_count,
                max_bytes: cfg.max_tool_definitions_bytes,
              )
          end
          catalog
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
