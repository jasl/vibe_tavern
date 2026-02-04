# frozen_string_literal: true

module SimpleInference
  # Back-compat default client.
  #
  # The current implementation targets the OpenAI-compatible HTTP API shape.
  # Future protocol implementations should live under `SimpleInference::Protocols`.
  class Client < Protocols::OpenAICompatible
  end
end
