# frozen_string_literal: true

# SimpleCov must be started before any application code is loaded
require "simplecov"
SimpleCov.start do
  enable_coverage :branch

  add_filter "/test/"
  add_filter "/tmp/"
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "tavern_kit"

require "minitest/autorun"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }
