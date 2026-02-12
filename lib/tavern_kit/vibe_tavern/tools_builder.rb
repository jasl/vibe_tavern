# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolsBuilder
      BuildResult = Data.define(:catalog, :executor)

      module_function

      def build(...)
        Builder.build(...)
      end
    end
  end
end

require_relative "tools_builder/builder"
