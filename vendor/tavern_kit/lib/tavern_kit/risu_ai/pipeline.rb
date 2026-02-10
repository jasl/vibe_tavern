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
      use_step TavernKit::RisuAI::PromptBuilder::Steps::Prepare, name: :prepare
      use_step TavernKit::RisuAI::PromptBuilder::Steps::Memory, name: :memory
      use_step TavernKit::RisuAI::PromptBuilder::Steps::TemplateAssembly, name: :template_assembly
      use_step TavernKit::RisuAI::PromptBuilder::Steps::CBS, name: :cbs
      use_step TavernKit::RisuAI::PromptBuilder::Steps::RegexScripts, name: :regex_scripts
      use_step TavernKit::RisuAI::PromptBuilder::Steps::Triggers, name: :triggers
      use_step TavernKit::RisuAI::PromptBuilder::Steps::PlanAssembly, name: :plan_assembly
    end
  end
end
