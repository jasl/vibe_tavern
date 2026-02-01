# frozen_string_literal: true

require_relative "invocation"
require_relative "preprocessors"
require_relative "packs/silly_tavern"

module TavernKit
  module SillyTavern
    module Macro
      # Parser-based SillyTavern macro engine (Wave 3).
      #
      # This is a Ruby re-implementation of ST's v2 macro pipeline:
      # - priority-ordered pre/post processors (see Preprocessors)
      # - nested macro evaluation in arguments and scoped content
      # - scoped macro pairing: {{macro}}...{{/macro}}
      # - variable shorthand expressions (e.g. {{.var+=1}})
      #
      # Design note: we intentionally implement "best-effort" parsing to remain
      # tolerant of user-provided prompt strings.
      class V2Engine < TavernKit::Macro::Engine::Base
        UNKNOWN_POLICIES = %i[keep empty].freeze
        VAR_NAME_PATTERN = /[a-zA-Z](?:[\w-]*[\w])?/.freeze
        VAR_EXPR_PATTERN =
          /\A(?<scope>[.$])(?<name>#{VAR_NAME_PATTERN})\s*(?<op>\+\+|--|\|\|=|\?\?=|\+=|-=|\|\||\?\?|==|!=|>=|<=|>|<|=)?(?<value>.*)\z/m.freeze

        def initialize(registry: Packs::SillyTavern.default_registry, unknown: :keep)
          unless UNKNOWN_POLICIES.include?(unknown)
            raise ArgumentError, "unknown must be one of: #{UNKNOWN_POLICIES.inspect}"
          end

          @registry = registry
          @unknown = unknown
        end

        def expand(text, environment:)
          return "" if text.nil?

          str = text.to_s
          return str if str.empty?

          preprocessed = Preprocessors.preprocess(str, environment: environment)
          raw_content_hash = Invocation.stable_hash(preprocessed)
          original_once = build_original_once(environment)

          out = evaluate_content(
            preprocessed,
            environment,
            raw_content_hash: raw_content_hash,
            original_once: original_once,
            context_offset: 0,
          )

          out = Preprocessors.postprocess(out, environment: environment)
          out = remove_unresolved_placeholders(out) if @unknown == :empty
          out
        end

        private

        ArgSpan = Data.define(:raw, :start_offset, :end_offset)

        # Implementation methods are split into:
        # - `silly_tavern/macro/v2_engine/evaluator.rb`
        # - `silly_tavern/macro/v2_engine/helpers.rb`
        # - `silly_tavern/macro/v2_engine/parser.rb`

        # Helper methods extracted to `silly_tavern/macro/v2_engine/helpers.rb` (Wave 6 large-file split).
      end
    end
  end
end

require_relative "v2_engine/evaluator"
require_relative "v2_engine/helpers"
require_relative "v2_engine/parser"
