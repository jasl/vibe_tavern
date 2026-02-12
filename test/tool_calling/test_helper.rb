# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"

require "simple_inference"
require "tavern_kit"

# App-owned pipeline (loaded manually for DB-free tests).
require_relative "../../lib/tavern_kit/vibe_tavern/prompt_builder/steps/prepare"
require_relative "../../lib/tavern_kit/vibe_tavern/prompt_builder/steps/plan_assembly"
require_relative "../../lib/tavern_kit/vibe_tavern/pipeline"
require_relative "../../lib/tavern_kit/vibe_tavern"

# DB-free tool-calling tests do not load the Rails environment (so initializers
# don't run). Configure token estimation root explicitly so the VibeTavern
# pipeline can build prompts without requiring Rails boot.
TavernKit::VibeTavern::TokenEstimation.configure(
  root: File.expand_path("../..", __dir__),
)

require_relative "../../lib/tavern_kit/vibe_tavern/tools_builder"
require_relative "../../lib/tavern_kit/vibe_tavern/tools/custom"
require_relative "../../lib/tavern_kit/vibe_tavern/tools/skills"
require_relative "../../lib/tavern_kit/vibe_tavern/tool_calling"
require_relative "../../lib/tavern_kit/vibe_tavern/tool_calling/tool_dispatcher"
require_relative "../../lib/tavern_kit/vibe_tavern/tool_calling/tool_loop_runner"
