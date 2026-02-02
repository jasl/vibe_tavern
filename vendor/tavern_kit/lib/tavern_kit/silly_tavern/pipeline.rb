# frozen_string_literal: true

require_relative "middleware/hooks"
require_relative "middleware/lore"
require_relative "middleware/entries"
require_relative "middleware/pinned_groups"
require_relative "middleware/injection"
require_relative "middleware/compilation"
require_relative "middleware/macro_expansion"
require_relative "middleware/plan_assembly"
require_relative "middleware/trimming"

module TavernKit
  module SillyTavern
    # Default SillyTavern middleware chain.
    #
    # Stage names are pinned by `docs/contracts/prompt-orchestration.md`.
    Pipeline = TavernKit::Prompt::Pipeline.new do
      use TavernKit::SillyTavern::Middleware::Hooks, name: :hooks
      use TavernKit::SillyTavern::Middleware::Lore, name: :lore
      use TavernKit::SillyTavern::Middleware::Entries, name: :entries
      use TavernKit::SillyTavern::Middleware::PinnedGroups, name: :pinned_groups
      use TavernKit::SillyTavern::Middleware::Injection, name: :injection
      use TavernKit::SillyTavern::Middleware::Compilation, name: :compilation
      use TavernKit::SillyTavern::Middleware::MacroExpansion, name: :macro_expansion
      use TavernKit::SillyTavern::Middleware::PlanAssembly, name: :plan_assembly
      use TavernKit::SillyTavern::Middleware::Trimming, name: :trimming
    end
  end
end
