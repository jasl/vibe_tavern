# frozen_string_literal: true

module TavernKit
  module Macro
    module Environment
      class Base
        def character_name = raise NotImplementedError
        def user_name = raise NotImplementedError

        def get_var(name, scope: :local) = raise NotImplementedError
        def set_var(name, value, scope: :local) = raise NotImplementedError
        def has_var?(name, scope: :local) = raise NotImplementedError
      end
    end
  end
end
