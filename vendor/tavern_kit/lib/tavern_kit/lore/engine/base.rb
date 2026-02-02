# frozen_string_literal: true

module TavernKit
  module Lore
    module Engine
      class Base
        # @param input [Lore::ScanInput] scan context
        # @return [Lore::Result] activation results
        def scan(input) = raise NotImplementedError
      end
    end
  end
end
