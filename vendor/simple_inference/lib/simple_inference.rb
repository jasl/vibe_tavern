# frozen_string_literal: true

require_relative "simple_inference/version"
require_relative "simple_inference/config"
require_relative "simple_inference/errors"
require_relative "simple_inference/http_adapter"
require_relative "simple_inference/response"
require_relative "simple_inference/openai"
require_relative "simple_inference/protocols/base"
require_relative "simple_inference/protocols/openai_compatible"
require_relative "simple_inference/client"

module SimpleInference
  class << self
    # Convenience constructor using RORO-style options hash.
    #
    # Example:
    #   client = SimpleInference.new(base_url: "...", api_key: "...")
    def new(options = {})
      Client.new(options)
    end
  end
end
