# frozen_string_literal: true

require_relative "risu_ai/utils"
require_relative "risu_ai/cbs"
require_relative "risu_ai/lore"
require_relative "risu_ai/lorebook"
require_relative "risu_ai/template_cards"
require_relative "risu_ai/regex_scripts"
require_relative "risu_ai/triggers"

module TavernKit
  # RisuAI platform layer (Wave 5+).
  #
  # This namespace intentionally stays independent from SillyTavern to avoid
  # “almost-the-same” helpers that drift over time.
  module RisuAI
  end
end
