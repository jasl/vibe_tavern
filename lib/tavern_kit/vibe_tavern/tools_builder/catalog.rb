# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolsBuilder
      # Minimal tool definitions contract used by ToolCalling.
      #
      # Implementations can be in-memory, database-backed, remote-backed, etc.
      #
      # This is intentionally small: ToolCalling only needs to (a) expose tool
      # JSON schemas to the model and (b) enforce allow/deny rules consistently
      # at execution time.
      class Catalog
        def definitions = raise NotImplementedError
        def openai_tools(expose: :model) = raise NotImplementedError
        def include?(name, expose: :model) = raise NotImplementedError
      end
    end
  end
end
