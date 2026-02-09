# frozen_string_literal: true

# Preload tokenizer assets at boot so request hot paths don't pay load cost.
# In production, strict mode should fail fast if any configured tokenizer asset
# is missing or invalid.

require Rails.root.join("lib/tavern_kit/vibe_tavern/token_estimation").to_s

TavernKit::VibeTavern::TokenEstimation
  .estimator
  .preload!(strict: Rails.env.production?)
