# frozen_string_literal: true

require_relative "middleware/prepare"
require_relative "middleware/plan_assembly"
require_relative "middleware/language_policy"
require_relative "infrastructure"

module TavernKit
  module VibeTavern
    # Default VibeTavern middleware chain (minimal).
    Pipeline = TavernKit::Prompt::Pipeline.new do
      use TavernKit::VibeTavern::Middleware::Prepare, name: :prepare
      use TavernKit::VibeTavern::Middleware::PlanAssembly, name: :plan_assembly
      use TavernKit::VibeTavern::Middleware::LanguagePolicy, name: :language_policy
    end

    TavernKit.run_load_hooks(:vibe_tavern, TavernKit::VibeTavern.infrastructure)
  end
end
