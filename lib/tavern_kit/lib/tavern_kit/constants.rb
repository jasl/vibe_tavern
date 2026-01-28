# frozen_string_literal: true

module TavernKit
  # Known generation triggers that can be passed to the prompt builder.
  # These control when World Info entries and Prompt Manager entries activate.
  #
  # - :normal     — Standard generation (default)
  # - :continue   — Continue/extend the last assistant message
  # - :impersonate — Generate as the user character
  # - :swipe      — Regenerate with different output (swipe left/right)
  # - :regenerate — Regenerate the last response
  # - :quiet      — Silent/background generation (e.g., summaries)
  GENERATION_TYPES = %i[normal continue impersonate swipe regenerate quiet].freeze

  # SillyTavern exports `injection_trigger` as numeric codes in preset JSON.
  # This mapping is inferred from ST's Prompt Manager behavior and public presets.
  #
  # The order matches ST's internal trigger type enum:
  # 0=Normal, 1=Continue, 2=Impersonate, 3=Swipe, 4=Regenerate, 5=Quiet
  TRIGGER_CODE_MAP = {
    0 => :normal,
    1 => :continue,
    2 => :impersonate,
    3 => :swipe,
    4 => :regenerate,
    5 => :quiet,
  }.freeze
end
