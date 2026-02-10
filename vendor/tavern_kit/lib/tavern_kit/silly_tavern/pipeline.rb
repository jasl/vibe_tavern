# frozen_string_literal: true

require_relative "prompt_builder/steps/hooks"
require_relative "prompt_builder/steps/lore"
require_relative "prompt_builder/steps/entries"
require_relative "prompt_builder/steps/pinned_groups"
require_relative "prompt_builder/steps/injection"
require_relative "prompt_builder/steps/compilation"
require_relative "prompt_builder/steps/macro_expansion"
require_relative "prompt_builder/steps/plan_assembly"
require_relative "prompt_builder/steps/trimming"

module TavernKit
  module SillyTavern
    # Default SillyTavern prompt-builder step chain.
    #
    # Stage names are pinned by `docs/contracts/prompt-orchestration.md`.
    Pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Hooks, name: :hooks
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Lore, name: :lore
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Entries, name: :entries
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::PinnedGroups, name: :pinned_groups
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Injection, name: :injection
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Compilation, name: :compilation
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::MacroExpansion, name: :macro_expansion
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::PlanAssembly, name: :plan_assembly
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Trimming, name: :trimming
    end
  end
end
