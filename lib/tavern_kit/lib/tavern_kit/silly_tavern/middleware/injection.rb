# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Middleware
      # Wave 4: ST injection stage (extension prompts + Author's Note + persona).
      class Injection < TavernKit::Prompt::Middleware::Base
        private

        def before(_ctx)
          # Implemented in a later Wave 4 commit.
        end
      end
    end
  end
end
