# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Middleware
      # Wave 4: resolves ST pinned prompt groups into block arrays.
      class PinnedGroups < TavernKit::Prompt::Middleware::Base
        private

        def before(_ctx)
          # Implemented in a later Wave 4 commit.
        end
      end
    end
  end
end
