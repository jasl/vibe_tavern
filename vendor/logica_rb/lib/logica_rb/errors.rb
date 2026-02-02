# frozen_string_literal: true

module LogicaRb
  class Error < StandardError; end

  class UnsupportedEngineError < Error
    attr_reader :engine

    def initialize(engine)
      @engine = engine
      super(engine.to_s)
    end
  end

  class MissingOptionalDependencyError < Error
    attr_reader :dependency

    def initialize(dependency, message = nil)
      @dependency = dependency
      super(message || "Missing optional dependency: #{dependency}")
    end
  end

  class PlanValidationError < Error; end

  class InvalidFormatError < Error; end

  class QueryOnlyViolationError < Error; end
end
