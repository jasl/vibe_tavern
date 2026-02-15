# frozen_string_literal: true

require "pathname"

module VibeTavernEval
  module Paths
    module_function

    def root
      @root ||= Pathname.new(__dir__).join("../../..").expand_path
    end
  end
end
