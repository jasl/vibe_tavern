# frozen_string_literal: true

require_relative "lib/tavern_kit/version"

Gem::Specification.new do |spec|
  spec.name = "tavern_kit"
  spec.version = TavernKit::VERSION
  spec.authors = ["jasl"]
  spec.email = ["jasl9187@hotmail.com"]

  spec.summary = "A Ruby toolkit for SillyTavern-style prompt building"
  spec.description = "TavernKit is a Ruby library for building highly customizable LLM chat prompts inspired by SillyTavern."
  spec.homepage = "https://github.com/jasl/vibe_tavern/lib/tavern_kit"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.metadata["homepage_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(".") ||
        f.start_with?(
          *%w[Gemfile bin/ test/ docs/ tmp/]
        ) ||
        (f.end_with?(".md") &&
          !%w[README.md].include?(f)
        )
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "js_regex_to_ruby", "~> 0"
  spec.add_dependency "tiktoken_ruby", "~> 0"
  spec.add_dependency "easy_talk", ">= 3.3.0", "~> 3"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
