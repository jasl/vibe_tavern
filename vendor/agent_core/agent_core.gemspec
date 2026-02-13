# frozen_string_literal: true

require_relative "lib/agent_core/version"

Gem::Specification.new do |spec|
  spec.name = "agent_core"
  spec.version = AgentCore::VERSION
  spec.authors = ["jasl"]
  spec.email = ["jasl9187@hotmail.com"]

  spec.summary = "Core primitives for building AI agent applications in Ruby."
  spec.description = "AgentCore provides the fundamental building blocks for AI agents: " \
                     "resource management (providers, chat history, memory, tools), " \
                     "prompt building pipelines, tool-calling execution loops, and a " \
                     "serializable Agent builder. It handles no IO directly — the host " \
                     "app implements provider and storage adapters."
  spec.homepage = "https://github.com/jasl/vibe_tavern/tree/main/vendor/agent_core"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage

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

  # No runtime dependencies — the gem is a library of primitives.
  # The host app brings its own HTTP client, database adapter, etc.
end
