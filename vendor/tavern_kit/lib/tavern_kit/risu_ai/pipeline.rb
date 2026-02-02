# frozen_string_literal: true

require_relative "middleware/prepare"
require_relative "middleware/memory"
require_relative "middleware/template_assembly"
require_relative "middleware/cbs"
require_relative "middleware/regex_scripts"
require_relative "middleware/triggers"
require_relative "middleware/plan_assembly"

module TavernKit
  module RisuAI
    # Default RisuAI middleware chain.
    Pipeline = TavernKit::Prompt::Pipeline.new do
      use TavernKit::RisuAI::Middleware::Prepare, name: :prepare
      use TavernKit::RisuAI::Middleware::Memory, name: :memory
      use TavernKit::RisuAI::Middleware::TemplateAssembly, name: :template_assembly
      use TavernKit::RisuAI::Middleware::CBS, name: :cbs
      use TavernKit::RisuAI::Middleware::RegexScripts, name: :regex_scripts
      use TavernKit::RisuAI::Middleware::Triggers, name: :triggers
      use TavernKit::RisuAI::Middleware::PlanAssembly, name: :plan_assembly
    end
  end
end
