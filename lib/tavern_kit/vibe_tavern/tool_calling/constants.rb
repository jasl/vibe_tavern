# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolCalling
      TOOL_USE_MODES = %i[enforced relaxed disabled].freeze
      TOOL_FAILURE_POLICIES = %i[fatal tolerated].freeze

      DEFAULT_MAX_TOOL_ARGS_BYTES = 200_000
      DEFAULT_MAX_TOOL_OUTPUT_BYTES = 200_000
      DEFAULT_MAX_TOOL_DEFINITIONS_COUNT = 128
      DEFAULT_MAX_TOOL_DEFINITIONS_BYTES = 200_000
    end
  end
end
