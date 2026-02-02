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

          # ST parity: turn_count is the number of user messages including the
          # current user input (when present). Apps may provide it explicitly.
          ctx.turn_count ||= infer_turn_count(ctx)
        end

        def after(ctx)
          ctx.hook_registry.run_after_build(ctx) if ctx.hook_registry.respond_to?(:run_after_build)
        end

        def infer_turn_count(ctx)
          history = TavernKit::ChatHistory.wrap(ctx.history)

          count =
            if history.respond_to?(:user_message_count)
              history.user_message_count
            else
              history.to_a.count { |m| m.role.to_sym == :user }
            end

          has_user_input = !ctx.user_message.to_s.strip.empty?
          count += 1 if has_user_input && ctx.generation_type.to_sym != :continue

          count
        rescue ArgumentError
          has_user_input = !ctx.user_message.to_s.strip.empty?
          has_user_input ? 1 : 0
        end
      end
    end
  end
end
