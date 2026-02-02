# frozen_string_literal: true

require_relative "base"

module TavernKit
  module Dialects
    # xAI chat dialect (OpenAI-like role/content list).
    class XAI < Base
      def convert(messages, **_opts)
        Array(messages).map { |m| { role: role_string(m.role), content: m.content.to_s } }
      end
    end
  end
end

TavernKit::Dialects.register(:xai, TavernKit::Dialects::XAI)
