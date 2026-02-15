# frozen_string_literal: true

module AgentCore
  # Global configuration for AgentCore.
  #
  # AgentCore is a library of primitives, but some cross-cutting concerns
  # (like media source policy) benefit from a single shared configuration.
  class Configuration
    # Whether URL-based media sources are allowed for multimodal blocks.
    # When false, :url sources will raise during content block initialization.
    attr_accessor :allow_url_media_sources

    # Optional whitelist of allowed URL schemes (e.g., %w[https]).
    # When nil, no scheme validation is performed.
    attr_accessor :allowed_media_url_schemes

    # Optional custom validator hook for media blocks.
    #
    # Called with the content block instance (ImageContent/DocumentContent/AudioContent).
    # Return truthy to allow, falsey to reject (raises ArgumentError).
    # The validator may also raise its own error.
    attr_accessor :media_source_validator

    def initialize
      @allow_url_media_sources = false
      @allowed_media_url_schemes = nil
      @media_source_validator = nil
    end
  end

  def self.config
    @config ||= Configuration.new
  end

  def self.configure
    yield(config)
  end

  def self.reset_config!
    @config = Configuration.new
  end
end
