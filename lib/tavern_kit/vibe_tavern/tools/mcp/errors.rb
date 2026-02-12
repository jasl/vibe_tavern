# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module Tools
      module MCP
        module Errors
          class TimeoutError < StandardError; end
          class ClosedError < StandardError; end
          class TransportError < StandardError; end
        end
      end
    end
  end
end
