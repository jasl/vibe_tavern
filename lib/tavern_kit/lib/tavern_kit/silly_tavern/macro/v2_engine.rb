# frozen_string_literal: true

require_relative "preprocessors"

module TavernKit
  module SillyTavern
    module Macro
      # Parser-based SillyTavern macro engine (Wave 3).
      #
      # The full implementation targets ST's experimental macro engine:
      # - scoped macros: {{if}}...{{/if}}
      # - macro flags: {{#if ...}} preserve whitespace
      # - typed args, list args, shorthand operators
      #
      # For now this is a small scaffold that runs preprocessors (legacy markers)
      # so downstream systems can safely adopt the V2Engine entrypoint early.
      class V2Engine < TavernKit::Macro::Engine::Base
        def expand(text, environment:)
          return "" if text.nil?

          str = text.to_s
          return str if str.empty?

          Preprocessors.preprocess(str, environment: environment)
        end
      end
    end
  end
end
