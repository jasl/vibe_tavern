# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Middleware
      # Wave 4: compile pinned groups + prompt entries into a single block list.
      class Compilation < TavernKit::Prompt::Middleware::Base
        private

        def before(_ctx)
          # Implemented in a later Wave 4 commit.
        end
      end
    end
  end
end
