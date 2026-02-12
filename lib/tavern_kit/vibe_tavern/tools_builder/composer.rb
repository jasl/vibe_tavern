# frozen_string_literal: true

require_relative "../tools/custom/catalog"

module TavernKit
  module VibeTavern
    module ToolsBuilder
      module Composer
        module_function

        def build(*definition_sets)
          defs = definition_sets.flatten.compact
          TavernKit::VibeTavern::Tools::Custom::Catalog.new(definitions: defs)
        end
      end
    end
  end
end
