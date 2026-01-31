# frozen_string_literal: true

require_relative "risu_ai/cbs"
require_relative "risu_ai/lorebook"

module TavernKit
  # RisuAI platform layer (Wave 5+).
  #
  # This namespace intentionally stays independent from SillyTavern to avoid
  # “almost-the-same” helpers that drift over time.
  module RisuAI
  end
end
