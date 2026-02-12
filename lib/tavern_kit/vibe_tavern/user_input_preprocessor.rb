# frozen_string_literal: true

require_relative "liquid_macros"

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
        # @param context [TavernKit::PromptBuilder::Context, nil] used for toggle lookup
        # @param enabled [Boolean, nil] override toggle lookup
        def call(text, variables_store:, assigns: {}, context: nil, enabled: nil, strict: false, on_error: :passthrough, registers: {})
          enabled = enabled.nil? ? enabled_from_context(context) : enabled
          return text.to_s unless enabled

          merged_registers = registers.is_a?(Hash) ? registers.dup : {}
          merged_registers[:context] ||= context if context

          TavernKit::VibeTavern::LiquidMacros.render(
            text,
            assigns: assigns,
            variables_store: variables_store,
            strict: strict,
            on_error: on_error,
            registers: merged_registers,
          )
        end

        def enabled_from_context(context, default: false)
          return default unless context

          toggles =
            if context.respond_to?(:toggles)
              context.toggles
            else
              context[:toggles]
            end

          return default unless toggles.is_a?(Hash)

          toggles[ENABLE_TOGGLE] == true
        end
      end
    end
  end
end
