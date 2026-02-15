# frozen_string_literal: true

module AgentCore
  module Observability
    # No-op instrumenter used by default.
    class NullInstrumenter < Instrumenter
      def publish(_name, _payload)
        nil
      end
    end
  end
end
