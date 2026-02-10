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
    # Step names are pinned by `docs/contracts/prompt-orchestration.md`.
    Pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :hooks, TavernKit::SillyTavern::PromptBuilder::Steps::Hooks
      use_step :lore, TavernKit::SillyTavern::PromptBuilder::Steps::Lore
      use_step :entries, TavernKit::SillyTavern::PromptBuilder::Steps::Entries
      use_step :pinned_groups, TavernKit::SillyTavern::PromptBuilder::Steps::PinnedGroups
      use_step :injection, TavernKit::SillyTavern::PromptBuilder::Steps::Injection
      use_step :compilation, TavernKit::SillyTavern::PromptBuilder::Steps::Compilation
      use_step :macro_expansion, TavernKit::SillyTavern::PromptBuilder::Steps::MacroExpansion
      use_step :plan_assembly, TavernKit::SillyTavern::PromptBuilder::Steps::PlanAssembly
      use_step :trimming, TavernKit::SillyTavern::PromptBuilder::Steps::Trimming
    end
  end
end
