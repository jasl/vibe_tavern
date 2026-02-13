# frozen_string_literal: true

# SimpleCov must be started before any application code is loaded
require "simplecov"
SimpleCov.start do
  enable_coverage :branch

  add_filter "/test/"
  add_filter "/tmp/"
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "agent_core"

require "minitest/autorun"
