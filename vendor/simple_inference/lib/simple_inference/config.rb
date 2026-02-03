# frozen_string_literal: true

module SimpleInference
  class Config
    attr_reader :base_url,
                :api_key,
                :api_prefix,
                :timeout,
                :open_timeout,
                :read_timeout,
                :adapter,
                :raise_on_error

    def initialize(options = {})
      opts = symbolize_keys(options || {})

      @base_url = normalize_base_url(
        opts[:base_url] || ENV["SIMPLE_INFERENCE_BASE_URL"] || "http://localhost:8000"
      )
      @api_key = (opts[:api_key] || ENV["SIMPLE_INFERENCE_API_KEY"]).to_s
      @api_key = nil if @api_key.empty?

      @api_prefix = normalize_api_prefix(
        opts.key?(:api_prefix) ? opts[:api_prefix] : ENV.fetch("SIMPLE_INFERENCE_API_PREFIX", "/v1")
      )

      # Avoid the common "/v1/v1" footgun when callers include "/v1" in base_url
      # and also use the default api_prefix of "/v1".
      @base_url = strip_api_prefix_from_base_url(@base_url, @api_prefix)

      @timeout = to_float_or_nil(opts[:timeout] || ENV["SIMPLE_INFERENCE_TIMEOUT"])
      @open_timeout = to_float_or_nil(opts[:open_timeout] || ENV["SIMPLE_INFERENCE_OPEN_TIMEOUT"])
      @read_timeout = to_float_or_nil(opts[:read_timeout] || ENV["SIMPLE_INFERENCE_READ_TIMEOUT"])

      @adapter = opts[:adapter]

      @raise_on_error = boolean_option(
        explicit: opts.fetch(:raise_on_error, nil),
        env_name: "SIMPLE_INFERENCE_RAISE_ON_ERROR",
        default: true
      )

      @default_headers = build_default_headers(opts[:headers] || {})
    end

    def headers
      @default_headers.dup
    end

    private

    def normalize_base_url(value)
      url = value.to_s.strip
      url = "http://localhost:8000" if url.empty?
      url.chomp("/")
    end

    def normalize_api_prefix(value)
      return "" if value.nil?

      prefix = value.to_s.strip
      return "" if prefix.empty?

      # Ensure it starts with / and does not end with /
      prefix = "/#{prefix}" unless prefix.start_with?("/")
      prefix.chomp("/")
    end

    def strip_api_prefix_from_base_url(base_url, api_prefix)
      return base_url if api_prefix.nil? || api_prefix.empty?
      return base_url unless base_url.end_with?(api_prefix)

      base_url[0...-api_prefix.length].chomp("/")
    end

    def to_float_or_nil(value)
      return nil if value.nil? || value == ""

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def boolean_option(explicit:, env_name:, default:)
      return !!explicit unless explicit.nil?

      env_value = ENV[env_name]
      return default if env_value.nil?

      %w[1 true yes on].include?(env_value.to_s.strip.downcase)
    end

    def build_default_headers(extra_headers)
      headers = {
        "Accept" => "application/json",
      }

      headers["Authorization"] = "Bearer #{@api_key}" if @api_key

      headers.merge(stringify_keys(extra_headers))
    end

    def symbolize_keys(hash)
      hash.each_with_object({}) do |(key, value), out|
        out[key.to_sym] = value
      end
    end

    def stringify_keys(hash)
      hash.each_with_object({}) do |(key, value), out|
        out[key.to_s] = value
      end
    end
  end
end
