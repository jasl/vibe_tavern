# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/generators")
loader.inflector.inflect(
  "type_inference" => "TypeInference",
  "cli" => "CLI",
  "errors" => "Error"
)
loader.setup

require_relative "logica_rb/errors"
