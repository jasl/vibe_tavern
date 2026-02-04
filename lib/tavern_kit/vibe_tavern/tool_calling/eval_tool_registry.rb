# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolCalling
      # Minimal tool registry used by the live eval harness.
      #
      # Keeping the model-facing tool list tiny helps reduce model variance and
      # makes failures easier to attribute to "tool calling reliability" rather
      # than tool selection mistakes.
      class EvalToolRegistry < ToolRegistry
        EVAL_TOOL_NAMES = %w[state_get state_patch].freeze

        def definitions
          super.select { |d| EVAL_TOOL_NAMES.include?(d.name) }
        end
      end
    end
  end
end
