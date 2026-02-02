# frozen_string_literal: true

module TavernKit
  module Macro
    module Engine
      class Base
        # @param text [String] template text with macro placeholders
        # @param environment [Macro::Environment::Base] execution environment
        # @return [String] expanded text
        def expand(text, environment:) = raise NotImplementedError
      end
    end
  end
end
