# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module Middleware
      # Stage: defaults and input normalization.
      #
      # This is intentionally small: it sets up the context for the rest of the
      # pipeline without pulling in any ST/RisuAI behaviors.
      class Prepare < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          ctx.token_estimator ||= TavernKit::TokenEstimator.default
          ctx.variables_store!

          normalize_runtime!(ctx)
        end

        def normalize_runtime!(ctx)
          return if ctx.runtime
          return unless ctx.key?(:runtime)

          ctx.runtime = TavernKit::Runtime::Base.build(ctx[:runtime], type: :app)
        end
      end
    end
  end
end
