# frozen_string_literal: true

module TavernKit
  module Macro
    module Registry
      class Base
        def register(name, handler, **metadata) = raise NotImplementedError
        def get(name) = raise NotImplementedError
        def has?(name) = raise NotImplementedError
      end
    end
  end
end
