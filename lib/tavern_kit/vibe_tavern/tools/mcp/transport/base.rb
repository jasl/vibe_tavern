# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module Tools
      module MCP
        module Transport
          class Base
            attr_accessor :on_stdout_line, :on_stderr_line

            def start = raise NotImplementedError
            def send_message(_hash) = raise NotImplementedError
            def close(timeout_s: 2.0) = raise NotImplementedError
          end
        end
      end
    end
  end
end
