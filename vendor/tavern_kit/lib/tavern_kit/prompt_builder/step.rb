# frozen_string_literal: true

module TavernKit
  class PromptBuilder
    # Base class for all prompt-builder pipeline steps.
    class Step
      # Name used when a step is registered without an explicit name.
      #
      # @return [Symbol]
      def self.step_name
        name.split("::").last
          .gsub(/Step$/, "")
          .gsub(/([a-z])([A-Z])/, '\1_\2')
          .downcase
          .to_sym
      end

      # Class-level hook: run before inner steps.
      #
      # @param state [TavernKit::PromptBuilder::State]
      # @param config [Object] typed step config (`StepClass::Config`)
      def self.before(_state, _config)
      end

      # Class-level hook: run after inner steps.
      #
      # @param state [TavernKit::PromptBuilder::State]
      # @param config [Object] typed step config (`StepClass::Config`)
      def self.after(_state, _config)
      end
    end
  end
end
