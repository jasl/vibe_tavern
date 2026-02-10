# frozen_string_literal: true

module TavernKit
  class PromptBuilder
    # Base class for all prompt-builder pipeline steps.
    class Step
      # @return [#call] the next step or terminal handler
      attr_reader :app

      # @return [Hash] step options
      attr_reader :options

      # @param app [#call] next step in chain
      # @param options [Hash] step-specific options
      def initialize(app, **options)
        @app = app
        @options = options
      end

      # Process the state through this step.
      #
      # Calls {#before}, then passes to the next step,
      # then calls {#after}.
      #
      # @param state [State] the builder state
      # @return [State] the processed state
      def call(state)
        step_name = option(:__step, self.class.step_name)
        previous_step_name = state.current_step
        state.current_step = step_name

        state.instrument(:step_start, name: step_name)
        before(state)
        @app.call(state)
        after(state)
        state.instrument(:step_finish, name: step_name)
        state
      rescue StandardError => e
        state&.instrument(:step_error, name: step_name, error: e)

        raise if e.is_a?(TavernKit::PipelineError)

        raise TavernKit::PipelineError.new("#{e.class}: #{e.message}", step: step_name), cause: e
      ensure
        state.current_step = previous_step_name if state
      end

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

      private

      def before(_state)
      end

      def after(_state)
      end

      # Helper to access an option with default.
      def option(key, default = nil)
        @options.fetch(key, default)
      end
    end
  end
end
