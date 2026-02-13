# frozen_string_literal: true

module MockLLM
  module V1
    class ModelsController < ApplicationController
      def index
        now = Time.current.to_i

        render json: {
          object: "list",
          data: [
            {
              id: "mock",
              object: "model",
              created: now,
              owned_by: "mock_llm",
            },
          ],
        }
      end
    end
  end
end
