# frozen_string_literal: true

require_relative "tools_builder/catalog"
require_relative "tools_builder/definition"
require_relative "tools_builder/filtered_catalog"
require_relative "tools_builder/catalog_snapshot"
require_relative "tools_builder/runtime_filtered_catalog"
require_relative "tools_builder/composer"
require_relative "tools/custom"
require_relative "tools/skills"
require_relative "tools_builder/builder"

module TavernKit
  module VibeTavern
    module ToolsBuilder
      module_function

      def build(...)
        Builder.build(...)
      end
    end
  end
end
