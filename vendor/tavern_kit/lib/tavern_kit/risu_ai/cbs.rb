# frozen_string_literal: true

require_relative "cbs/engine"
require_relative "cbs/environment"
require_relative "cbs/macros"

module TavernKit
  module RisuAI
    # RisuAI's CBS macro language entrypoint.
    #
    # Note: This is a convenience API used by characterization tests. The
    # pipeline integration will wire a CBS engine via Core interfaces.
    module CBS
      module_function

      def render(text, environment: nil, **context)
        env = environment || TavernKit::RisuAI::CBS::Environment.build(**context)
        TavernKit::RisuAI::CBS::Engine.new.expand(text.to_s, environment: env)
      end
    end
  end
end
