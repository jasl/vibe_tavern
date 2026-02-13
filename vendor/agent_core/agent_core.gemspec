# frozen_string_literal: true

require_relative "lib/agent_core/version"

Gem::Specification.new do |spec|
  spec.name = "agent_core"
  spec.version = AgentCore::VERSION
  spec.authors = ["jasl"]
  spec.email = ["jasl9187@hotmail.com"]

  spec.summary = "TODO: Write a short summary, because RubyGems requires one."
  spec.description = "TODO: Write a longer description or delete this line."
  spec.homepage = "https://github.com/jasl/vibe_tavern/tree/main/vendor/agent_core"
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

  spec.add_dependency "tiktoken_ruby", "~> 0"
  spec.add_dependency "tokenizers", "~> 0"
  spec.add_dependency "simple_inference", "~> 0"
  spec.add_dependency "easy_talk", ">= 3.3.0", "~> 3"
end
