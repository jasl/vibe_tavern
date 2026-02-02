# frozen_string_literal: true

require_relative "lib/logica_rb/version"

Gem::Specification.new do |spec|
  spec.name = "logica_rb"
  spec.version = LogicaRb::VERSION
  spec.authors = ["jasl"]
  spec.email = ["jasl9187@hotmail.com"]

  spec.summary = "Logica to SQL transpiler for SQLite and PostgreSQL"
  spec.description = "Ruby Logica compiler that outputs SQL and execution plans for SQLite and PostgreSQL."
  spec.homepage = "https://github.com/jasl/logica_rb"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.4.0"

  spec.metadata["homepage_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  spec.files =
    Dir.chdir(__dir__) do
      files = []

      files.concat(Dir.glob("lib/**/*", File::FNM_DOTMATCH))
      files.concat(Dir.glob("exe/**/*", File::FNM_DOTMATCH))
      files.concat(%w[README.md CHANGELOG.md SECURITY.md LICENSE.txt])
      files.concat(Dir.glob("docs/**/*", File::FNM_DOTMATCH))
      files.concat(Dir.glob("sig/**/*", File::FNM_DOTMATCH))

      files.select { |f| File.file?(f) }.uniq.sort
    end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "csv", "~> 3.3"
  spec.add_dependency "zeitwerk", "~> 2"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
