# frozen_string_literal: true

require_relative "directives/directive_definition"
require_relative "directives/registry"
require_relative "directives/schema"
require_relative "directives/parser"
require_relative "directives/validator"
require_relative "directives/runner"

module AgentCore
  module Contrib
    # Structured "directives envelope" output helpers.
    #
    # This is app-side glue (not AgentCore core). It provides:
    # - response_format JSON schema / JSON object fallbacks
    # - parsing + validation + normalization
    # - a small runner with retries ("repair") for brittle models
    module Directives
      DEFAULT_MODES = %i[json_schema json_object prompt_only].freeze
      DEFAULT_REPAIR_RETRY_COUNT = 1

      ENVELOPE_OUTPUT_INSTRUCTIONS = <<~TEXT.strip
        Return a single JSON object and nothing else (no Markdown, no code fences).

        JSON shape:
        - assistant_text: String (always present)
        - directives: Array (always present)
        - Each directive: { type: String, payload: Object }
      TEXT
    end
  end
end
