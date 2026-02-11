# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module PromptBuilder
      module Steps
        module Hooks
          extend TavernKit::PromptBuilder::Step

          Config =
            Data.define do
              def self.from_hash(raw)
                return raw if raw.is_a?(self)

                raise ArgumentError, "hooks step config must be a Hash" unless raw.is_a?(Hash)
                raw.each_key do |key|
                  raise ArgumentError, "hooks step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
                end

                if raw.any?
                  raise ArgumentError, "hooks step does not accept step config keys: #{raw.keys.inspect}"
                end

                new
              end
            end

          def self.before(ctx, _config)
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

          def self.after(ctx, _config)
            ctx.hook_registry.run_after_build(ctx) if ctx.hook_registry.respond_to?(:run_after_build)
          end

          class << self
            private

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
  end
end
