# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Middleware
      class Hooks < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          ctx.preset ||= TavernKit::SillyTavern::Preset.new
          ctx.hook_registry ||= TavernKit::SillyTavern::HookRegistry.new
          ctx.injection_registry ||= TavernKit::SillyTavern::InjectionRegistry.new
          ctx.token_estimator ||= TavernKit::TokenEstimator.default

          ctx.hook_registry.run_before_build(ctx) if ctx.hook_registry.respond_to?(:run_before_build)

          # Allow hooks to populate required inputs.
          ctx.validate!
        end

        def after(ctx)
          ctx.hook_registry.run_after_build(ctx) if ctx.hook_registry.respond_to?(:run_after_build)
        end
      end
    end
  end
end
