# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolsBuilder
      module Support
        module Envelope
          module_function

          def ok_envelope(tool_name, data = {})
            {
              ok: true,
              tool_name: tool_name.to_s,
              data: data.is_a?(Hash) ? data : { value: data },
              warnings: [],
              errors: [],
            }
          end

          def error_envelope(tool_name, code:, message:)
            {
              ok: false,
              tool_name: tool_name.to_s,
              data: {},
              warnings: [],
              errors: [{ code: code.to_s, message: message.to_s }],
            }
          end
        end
      end
    end
  end
end
