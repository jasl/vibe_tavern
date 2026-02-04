# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"

require "simple_inference"
require "tavern_kit"

# App-owned pipeline (loaded manually for DB-free tests).
require_relative "../../lib/tavern_kit/vibe_tavern/middleware/prepare"
require_relative "../../lib/tavern_kit/vibe_tavern/middleware/plan_assembly"
require_relative "../../lib/tavern_kit/vibe_tavern/pipeline"
require_relative "../../lib/tavern_kit/vibe_tavern"

require_relative "../../lib/tavern_kit/vibe_tavern/tool_calling/tool_registry"
require_relative "../../lib/tavern_kit/vibe_tavern/tool_calling/tool_dispatcher"
require_relative "../../lib/tavern_kit/vibe_tavern/tool_calling/tool_loop_runner"
