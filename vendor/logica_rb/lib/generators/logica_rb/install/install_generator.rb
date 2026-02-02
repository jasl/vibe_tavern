# frozen_string_literal: true

require "logica_rb"

begin
  require "rails/generators"
rescue LoadError
  raise LogicaRb::MissingOptionalDependencyError.new(
    "railties",
    'Rails::Generators is required for logica_rb generators. Add `gem "railties"` (or install Rails).'
  )
end

module LogicaRb
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_logica_directory
        empty_directory "app/logica"
        template "hello.l", "app/logica/hello.l"
      end

      def create_initializer
        template "logica_rb.rb", "config/initializers/logica_rb.rb"
      end
    end
  end
end
