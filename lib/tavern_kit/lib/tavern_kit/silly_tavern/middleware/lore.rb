# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Middleware
      # Wave 4: ST World Info orchestration.
      #
      # Stage contract is pinned in docs/rewrite/wave4-contracts.md.
      class Lore < TavernKit::Prompt::Middleware::Base
        private

        def before(_ctx)
          # Implemented in a later Wave 4 commit (kept as a no-op placeholder).
        end
      end
    end
  end
end
