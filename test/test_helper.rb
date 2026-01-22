require "simplecov"
SimpleCov.start "rails" do
  # Track coverage for app code only
  add_filter "/test/"
  add_filter "/config/"
  add_filter "/db/"
  add_filter "/vendor/"
  add_filter "/lib/"

  # Group coverage by component type
  add_group "Controllers", "app/controllers"
  add_group "Models", "app/models"
  add_group "Services", "app/services"
  add_group "Jobs", "app/jobs"
  add_group "Channels", "app/channels"
  add_group "Helpers", "app/helpers"
  add_group "Presenters", "app/presenters"
  add_group "Queries", "app/queries"

  # Set minimum coverage threshold (optional, set to 0 initially)
  # minimum_coverage 80
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
