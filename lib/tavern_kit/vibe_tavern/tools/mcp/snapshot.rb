# frozen_string_literal: true

require_relative "constants"

module TavernKit
  module VibeTavern
    module Tools
      module MCP
        Snapshot =
          Data.define(:definitions, :mapping, :clients) do
            def initialize(definitions:, mapping:, clients:)
              super(
                definitions: Array(definitions),
                mapping: mapping.is_a?(Hash) ? mapping : {},
                clients: clients.is_a?(Hash) ? clients : {},
              )
            end

            def close
              clients.each_value do |client|
                begin
                  client.close
                rescue StandardError
                  nil
                end
              end

              nil
            end
          end
      end
    end
  end
end
