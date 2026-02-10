# frozen_string_literal: true

require_relative "prompt_builder/steps/prepare"
require_relative "prompt_builder/steps/memory"
require_relative "prompt_builder/steps/template_assembly"
require_relative "prompt_builder/steps/cbs"
require_relative "prompt_builder/steps/regex_scripts"
require_relative "prompt_builder/steps/triggers"
require_relative "prompt_builder/steps/plan_assembly"

module TavernKit
  module RisuAI
    # Default RisuAI prompt-builder step chain.
    Pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :prepare, TavernKit::RisuAI::PromptBuilder::Steps::Prepare
      use_step :memory, TavernKit::RisuAI::PromptBuilder::Steps::Memory
      use_step :template_assembly, TavernKit::RisuAI::PromptBuilder::Steps::TemplateAssembly
      use_step :cbs, TavernKit::RisuAI::PromptBuilder::Steps::CBS
      use_step :regex_scripts, TavernKit::RisuAI::PromptBuilder::Steps::RegexScripts
      use_step :triggers, TavernKit::RisuAI::PromptBuilder::Steps::Triggers
      use_step :plan_assembly, TavernKit::RisuAI::PromptBuilder::Steps::PlanAssembly
    end
  end
end
