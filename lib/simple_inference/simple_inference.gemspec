# frozen_string_literal: true

require_relative "lib/simple_inference/version"

Gem::Specification.new do |spec|
  spec.name = "simple_inference"
  spec.version = SimpleInference::VERSION
  spec.authors = ["jasl"]
  spec.email = ["jasl9187@hotmail.com"]

  spec.summary = "A lightweight, Fiber-friendly Ruby client for OpenAI-compatible LLM APIs."
  spec.description =
    "A lightweight, Fiber-friendly Ruby client for OpenAI-compatible LLM APIs. (chat, embeddings, audio, rerank, health)."
  spec.homepage = "https://github.com/jasl/simple_inference.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

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
end
