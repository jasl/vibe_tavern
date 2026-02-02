# frozen_string_literal: true

require_relative "runtime/base"

module TavernKit
  # Shared runtime contracts (Core).
  #
  # A runtime is the application-owned state that must stay synchronized with
  # a prompt-building pipeline. Platform layers (ST/RisuAI) can extend this
  # module with their own Runtime implementations.
  module Runtime
  end
end
