# frozen_string_literal: true

module TavernKit
  module VibeTavern
    # Optional app-layer preprocessing for end-user input.
    #
    # Upstream apps like ST/RisuAI expand macros/scripts on user input before it
    # is appended to the chat history. For the Rails rewrite we keep this
    # behavior *disabled by default* and recommend applying it at the app layer
    # (pre-persistence), so prompt building stays deterministic and side-effect
    # free.
    class UserInputPreprocessor
      ENABLE_TOGGLE = :expand_user_input_macros

      class << self
        # @param text [String]
        # @param variables_store [TavernKit::VariablesStore::Base]
        # @param assigns [Hash] Liquid assigns
        # @param runtime [TavernKit::Runtime::Base, nil] used for toggle lookup
        # @param enabled [Boolean, nil] override toggle lookup
        def call(text, variables_store:, assigns: {}, runtime: nil, enabled: nil, strict: false, on_error: :passthrough, registers: {})
          enabled = enabled.nil? ? enabled_from_runtime(runtime) : enabled
          return text.to_s unless enabled

          merged_registers = registers.is_a?(Hash) ? registers.dup : {}
          merged_registers[:runtime] ||= runtime if runtime

          TavernKit::VibeTavern::LiquidMacros.render(
            text,
            assigns: assigns,
            variables_store: variables_store,
            strict: strict,
            on_error: on_error,
            registers: merged_registers,
          )
        end

        def enabled_from_runtime(runtime, default: false)
          return default unless runtime

          toggles =
            if runtime.respond_to?(:toggles)
              runtime.toggles
            else
              runtime[:toggles]
            end

          return default unless toggles.is_a?(Hash)

          toggles[ENABLE_TOGGLE] == true
        end
      end
    end
  end
end
