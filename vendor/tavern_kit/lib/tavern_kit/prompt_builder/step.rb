# frozen_string_literal: true

module TavernKit
  class PromptBuilder
    # Interface contract for all prompt-builder pipeline steps.
    #
    # Steps are modules that `extend Step` and implement:
    # - `Config.from_hash`
    # - `self.before(state, config)` / `self.after(state, config)` hooks
    #
    # Important: do not store per-run state in module instance variables.
    # Keep per-run data in the provided `state` and `config` objects.
    module Step
      # Name used when a step is registered without an explicit name.
      #
      # @return [Symbol]
      def step_name
        name.split("::").last
          .gsub(/Step$/, "")
          .gsub(/([a-z])([A-Z])/, '\1_\2')
          .downcase
          .to_sym
      end

      # Hook: run before inner steps.
      #
      # @param state [TavernKit::PromptBuilder::State]
      # @param config [Object] typed step config (`StepModule::Config`)
      def before(_state, _config)
      end

      # Hook: run after inner steps.
      #
      # @param state [TavernKit::PromptBuilder::State]
      # @param config [Object] typed step config (`StepModule::Config`)
      def after(_state, _config)
      end
    end
  end
end
