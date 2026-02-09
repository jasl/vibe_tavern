#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "optparse"
require "set"
require "tempfile"
require "time"
require "uri"

ENV["RAILS_ENV"] ||= "development"
require_relative "../config/environment"

module DownloadTokenizers
  module_function

  def run(argv)
    options = parse_options(argv)

    sources = TavernKit::VibeTavern::TokenEstimation.sources
    if options[:only].any?
      allowed = options[:only]
      sources = sources.select { |s| allowed.include?(s.fetch(:hint)) }
    end

    if sources.empty?
      warn "No tokenizer sources selected."
      return 2
    end

    failures = []

    sources.each do |source|
      hint = source.fetch(:hint)
      dest = Rails.root.join(source.fetch(:relative_path))
      dest_dir = dest.dirname

      if options[:check]
        ok = check_file(dest, hint: hint)
        failures << hint unless ok
        next
      end

      FileUtils.mkdir_p(dest_dir)

      if dest.exist? && !options[:force]
        puts "skip: #{hint} (already exists)"
        next
      end

      url = build_url(source)
      puts "download: #{hint} -> #{dest} (#{url})"

      tmp = Tempfile.new(["tokenizer", ".json"], dest_dir.to_s)
      tmp.binmode

      response = http_download(url, io: tmp, token: hf_token)
      tmp.flush
      tmp.close

      validate_json!(tmp.path)
      validate_hf_tokenizers!(tmp.path)

      FileUtils.mv(tmp.path, dest.to_s)
      tmp = nil

      write_source_metadata!(
        dest_dir.join("source.json"),
        source: source,
        url: url,
        response: response,
      )

      puts "ok: #{hint}"
    rescue StandardError => e
      failures << hint
      warn "error: #{hint}: #{e.class}: #{e.message}"
    ensure
      tmp&.close! if tmp
    end

    return 0 if failures.empty?

    warn "Failed: #{failures.uniq.join(", ")}"
    1
  end

  def parse_options(argv)
    opts = {
      only: Set.new,
      force: false,
      check: false,
    }

    OptionParser.new do |parser|
      parser.banner = "Usage: script/download_tokenizers.rb [options]"

      parser.on("--only x,y,z", Array, "Only download specific hints (e.g. deepseek,qwen3)") do |list|
        list.each { |hint| opts[:only] << hint.to_s.strip }
      end

      parser.on("--force", "Overwrite existing files") do
        opts[:force] = true
      end

      parser.on("--check", "Check that expected files exist and are valid") do
        opts[:check] = true
      end

      parser.on("-h", "--help", "Show help") do
        puts parser
        exit 0
      end
    end.parse!(argv)

    opts[:only].delete("")
    opts
  end

  def hf_token
    ENV.fetch("HF_TOKEN", "").to_s.strip.presence ||
      ENV.fetch("HUGGINGFACE_HUB_TOKEN", "").to_s.strip.presence
  end

  def build_url(source)
    repo = source.fetch(:hf_repo)
    rev = source.fetch(:revision)
    "https://huggingface.co/#{repo}/resolve/#{rev}/tokenizer.json"
  end

  def http_download(url, io:, token:)
    uri = URI.parse(url)
    max_redirects = 5

    max_redirects.times do
      response = nil
      redirect_location = nil

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{token}" if token

        http.request(request) do |res|
          response = res

          case res
          when Net::HTTPRedirection
            redirect_location = res["location"].to_s
          when Net::HTTPSuccess
            res.read_body { |chunk| io.write(chunk) }
          else
            raise "HTTP #{res.code}: #{res.message}"
          end
        end
      end

      if response.is_a?(Net::HTTPRedirection)
        raise "Redirect with no location" if redirect_location.to_s.empty?

        redirected = URI.parse(redirect_location)
        uri = redirected.relative? ? uri.merge(redirect_location) : redirected
        next
      end

      return response if response.is_a?(Net::HTTPSuccess)

      raise "No response" unless response
    end

    raise "Too many redirects"
  end

  def validate_json!(path)
    JSON.parse(File.read(path))
  rescue JSON::ParserError => e
    raise "Invalid JSON: #{e.message}"
  end

  def validate_hf_tokenizers!(path)
    require "tokenizers"
    Tokenizers.from_file(path)
  rescue LoadError
    warn "warn: tokenizers gem not available; skipping Tokenizers.from_file validation"
  end

  def write_source_metadata!(path, source:, url:, response:)
    meta = {
      hint: source.fetch(:hint),
      hf_repo: source.fetch(:hf_repo),
      revision: source.fetch(:revision),
      url: url,
      etag: response["etag"],
      x_repo_commit: response["x-repo-commit"],
      downloaded_at: Time.now.utc.iso8601,
    }

    File.write(path, JSON.pretty_generate(meta) + "\n")
  end

  def check_file(path, hint:)
    unless path.exist?
      warn "missing: #{hint} -> #{path}"
      return false
    end

    validate_json!(path.to_s)
    validate_hf_tokenizers!(path.to_s)

    puts "ok: #{hint} (#{path})"
    true
  rescue StandardError => e
    warn "invalid: #{hint} -> #{path}: #{e.class}: #{e.message}"
    false
  end
end

exit DownloadTokenizers.run(ARGV)
