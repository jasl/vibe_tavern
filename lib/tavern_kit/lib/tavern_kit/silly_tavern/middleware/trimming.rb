# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Middleware
      # Wave 4: ST token budget enforcement (delegates to Core Trimmer).
      class Trimming < TavernKit::Prompt::Middleware::Base
        private

        def before(_ctx)
          # Implemented in a later Wave 4 commit.
        end
      end
    end
  end
end
