# frozen_string_literal: true

module TavernKit
  module VibeTavern
    # Default VibeTavern middleware chain (minimal).
    Pipeline = TavernKit::Prompt::Pipeline.new do
      use TavernKit::VibeTavern::Middleware::Prepare, name: :prepare
      use TavernKit::VibeTavern::Middleware::PlanAssembly, name: :plan_assembly
    end
  end
end
