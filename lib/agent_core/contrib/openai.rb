# frozen_string_literal: true

module AgentCore
  module Contrib
    module OpenAI
      RESERVED_CHAT_COMPLETIONS_KEYS = %i[
        model
        messages
        tools
        tool_choice
        response_format
        stream
        stream_options
      ].freeze
    end
  end
end
