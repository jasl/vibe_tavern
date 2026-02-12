# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"

require "tavern_kit"

# App-owned pipeline (loaded manually for DB-free tests).
require_relative "../../lib/tavern_kit/vibe_tavern/prompt_builder/steps/prepare"
require_relative "../../lib/tavern_kit/vibe_tavern/prompt_builder/steps/plan_assembly"
require_relative "../../lib/tavern_kit/vibe_tavern/prompt_builder/steps/available_skills"
require_relative "../../lib/tavern_kit/vibe_tavern/prompt_builder/steps/language_policy"
require_relative "../../lib/tavern_kit/vibe_tavern/pipeline"
require_relative "../../lib/tavern_kit/vibe_tavern"

# DB-free skills tests do not load the Rails environment. Configure token
# estimation root explicitly so the VibeTavern pipeline can build prompts.
TavernKit::VibeTavern::TokenEstimation.configure(
  root: File.expand_path("../..", __dir__),
)

require_relative "../../lib/tavern_kit/vibe_tavern/tools/skills"
require_relative "../../lib/tavern_kit/vibe_tavern/runner_config"
require_relative "../../lib/tavern_kit/vibe_tavern/prompt_runner"
