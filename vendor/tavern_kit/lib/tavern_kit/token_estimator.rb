# frozen_string_literal: true

require "tiktoken_ruby"

module TavernKit
  # Token counting utility with a pluggable adapter interface.
  class TokenEstimator
    Tokenization =
      Data.define(:backend, :token_count, :ids, :tokens, :offsets, :details) do
        def initialize(backend:, token_count:, ids: nil, tokens: nil, offsets: nil, details: nil)
          super(
            backend: backend.to_s,
            token_count: Integer(token_count),
            ids: ids,
            tokens: tokens,
            offsets: offsets,
            details: details.is_a?(Hash) ? details : {},
          )
        end

        def detailed? = !!(ids || tokens || offsets)
      end

    module Adapter
      class Base
        def estimate(text, model_hint: nil) = raise NotImplementedError

        def describe(model_hint: nil) = { backend: self.class.name }

        def tokenize(text, model_hint: nil)
          Tokenization.new(
            backend: describe(model_hint: model_hint).fetch(:backend, self.class.name),
            token_count: estimate(text, model_hint: model_hint),
          )
        end
      end

      class Tiktoken < Base
        DEFAULT_ENCODING = "cl100k_base"
        Selection = Data.define(:encoding, :source)

        def initialize(default_encoding: DEFAULT_ENCODING)
          @default = ::Tiktoken.get_encoding(default_encoding)
          @encodings = {}
        end

        def estimate(text, model_hint: nil)
          encoding_for(model_hint).encode(text.to_s).length
        end

        def tokenize(text, model_hint: nil)
          encoding = encoding_for(model_hint)
          ids = encoding.encode(text.to_s)

          Tokenization.new(
            backend: "tiktoken",
            token_count: ids.length,
            ids: ids,
            # NOTE: `tiktoken_ruby` cannot reliably decode a *single* token id
            # into valid UTF-8 (emoji and other multi-byte sequences can split
            # across tokens). For debug, ids are still useful; leave tokens and
            # offsets unset rather than raising.
            tokens: nil,
            offsets: nil,
            details: describe(model_hint: model_hint),
          )
        end

        def describe(model_hint: nil)
          selection = selection_for(model_hint)
          {
            backend: "tiktoken",
            encoding: selection.encoding.name.to_s,
            source: selection.source.to_s,
          }
        end

        private

        def encoding_for(model_hint)
          selection_for(model_hint).encoding
        end

        def selection_for(model_hint)
          return Selection.new(encoding: @default, source: :default) if model_hint.nil?

          key = model_hint.to_s
          return Selection.new(encoding: @default, source: :default) if key.empty?

          # Cache the encoding per model hint. This is a CPU-bound hot path when
          # trimming/budgeting repeatedly estimates token counts.
          @encodings[key] ||= begin
            resolved = ::Tiktoken.encoding_for_model(key)
            Selection.new(encoding: (resolved || @default), source: (resolved ? :model : :default))
          rescue StandardError
            Selection.new(encoding: @default, source: :default)
          end
        rescue StandardError
          Selection.new(encoding: @default, source: :default)
        end
      end

      class HuggingFaceTokenizers < Base
        DEFAULT_CACHE_MAX_SIZE = 16

        def initialize(tokenizer_path:, cache: nil)
          @tokenizer_path = tokenizer_path.to_s
          @cache = cache || TavernKit::LRUCache.new(max_size: DEFAULT_CACHE_MAX_SIZE)
        end

        def estimate(text, model_hint: nil)
          tokenizer.encode(text.to_s, add_special_tokens: false).ids.length
        end

        def tokenize(text, model_hint: nil)
          encoding = tokenizer.encode(text.to_s, add_special_tokens: false)
          ids = encoding.ids

          Tokenization.new(
            backend: "hf_tokenizers",
            token_count: ids.length,
            ids: ids,
            tokens: encoding.tokens,
            offsets: encoding.offsets,
            details: describe(model_hint: model_hint),
          )
        end

        def describe(model_hint: nil)
          {
            backend: "hf_tokenizers",
            tokenizer_path: @tokenizer_path,
          }
        end

        def preload!
          tokenizer
          true
        end

        private

        def tokenizer
          @cache.fetch(@tokenizer_path) do
            require "tokenizers"
            Tokenizers.from_file(@tokenizer_path)
          end
        end
      end

      class Heuristic < Base
        DEFAULT_CHARS_PER_TOKEN = 4.0

        def initialize(chars_per_token: DEFAULT_CHARS_PER_TOKEN)
          @chars_per_token = Float(chars_per_token)
          @chars_per_token = DEFAULT_CHARS_PER_TOKEN if @chars_per_token <= 0
        rescue ArgumentError, TypeError
          @chars_per_token = DEFAULT_CHARS_PER_TOKEN
        end

        def estimate(text, model_hint: nil)
          s = text.to_s
          return 0 if s.empty?

          (s.length.fdiv(@chars_per_token)).ceil
        end

        def describe(model_hint: nil)
          {
            backend: "heuristic",
            chars_per_token: @chars_per_token,
          }
        end
      end
    end

    def self.default
      @default ||= new
    end

    def initialize(adapter: Adapter::Tiktoken.new, registry: nil)
      @adapter = adapter
      @registry = registry
      @heuristics = {}
      @hf_tokenizer_cache = TavernKit::LRUCache.new(max_size: Adapter::HuggingFaceTokenizers::DEFAULT_CACHE_MAX_SIZE)
      @hf_adapters = {}
      @fallback_heuristic = Adapter::Heuristic.new
    end

    def estimate(text, model_hint: nil)
      entry = resolve_registry_entry(model_hint)
      resolved = resolve_adapter(model_hint, entry: entry)
      resolved.estimate(text, model_hint: model_hint)
    rescue StandardError, LoadError
      begin
        if resolved && resolved != @adapter
          return @adapter.estimate(text, model_hint: model_hint)
        end
      rescue StandardError, LoadError
        # ignore and fall through
      end

      begin
        @fallback_heuristic.estimate(text, model_hint: model_hint)
      rescue StandardError
        0
      end
    end

    def tokenize(text, model_hint: nil)
      entry = resolve_registry_entry(model_hint)
      resolved = resolve_adapter(model_hint, entry: entry)

      if resolved.respond_to?(:tokenize)
        resolved.tokenize(text, model_hint: model_hint)
      else
        Tokenization.new(
          backend: resolved.class.name,
          token_count: resolved.estimate(text, model_hint: model_hint),
          details: describe(model_hint: model_hint),
        )
      end
    rescue StandardError, LoadError
      begin
        if resolved && resolved != @adapter && @adapter.respond_to?(:tokenize)
          return @adapter.tokenize(text, model_hint: model_hint)
        end
      rescue StandardError, LoadError
        # ignore and fall through
      end

      Tokenization.new(
        backend: "heuristic",
        token_count: @fallback_heuristic.estimate(text, model_hint: model_hint),
        details: @fallback_heuristic.describe(model_hint: model_hint),
      )
    rescue StandardError
      Tokenization.new(backend: "unknown", token_count: 0)
    end

    def preload!(strict: false)
      return { loaded: [], failed: [] } unless @registry.is_a?(Hash)

      paths = registry_hf_tokenizer_paths(@registry)
      loaded = []
      failed = []

      paths.each do |path|
        begin
          adapter = @hf_adapters[path] ||= Adapter::HuggingFaceTokenizers.new(tokenizer_path: path, cache: @hf_tokenizer_cache)
          adapter.preload!
          loaded << path
        rescue StandardError, LoadError => e
          failed << { path: path, error_class: e.class.name, message: e.message }
        end
      end

      if strict == true && failed.any?
        msg = failed.map { |f| "#{f[:path]} (#{f[:error_class]}: #{f[:message]})" }.join(", ")
        raise ArgumentError, "Failed to preload tokenizers: #{msg}"
      end

      { loaded: loaded, failed: failed }
    end

    def describe(model_hint: nil)
      entry = resolve_registry_entry(model_hint)
      adapter = resolve_adapter(model_hint, entry: entry)

      raw = adapter.respond_to?(:describe) ? adapter.describe(model_hint: model_hint) : { backend: adapter.class.name }
      info = raw.is_a?(Hash) ? raw : { backend: adapter.class.name }

      if entry
        info = info.dup
        info[:registry] = true
        info[:source] ||= "registry"
      end

      info
    rescue StandardError
      { backend: @adapter.class.name }
    end

    private

    def resolve_adapter(model_hint, entry: nil)
      entry ||= resolve_registry_entry(model_hint)
      return @adapter unless entry

      family =
        entry[:tokenizer_family]
          .to_s
          .strip
          .downcase
          .tr("-", "_")
          .to_sym

      case family
      when :heuristic
        chars_per_token = entry[:chars_per_token]
        chars_per_token = Adapter::Heuristic::DEFAULT_CHARS_PER_TOKEN if chars_per_token.nil?

        key =
          begin
            Float(chars_per_token)
          rescue ArgumentError, TypeError
            Adapter::Heuristic::DEFAULT_CHARS_PER_TOKEN
          end

        @heuristics[key] ||= Adapter::Heuristic.new(chars_per_token: key)
      when :hf_tokenizers, :huggingface_tokenizers, :tokenizers
        path = entry[:tokenizer_path]
        path = path.to_s
        return @adapter if path.empty?

        @hf_adapters[path] ||= Adapter::HuggingFaceTokenizers.new(tokenizer_path: path, cache: @hf_tokenizer_cache)
      else
        @adapter
      end
    end

    def registry_hf_tokenizer_paths(registry)
      registry
        .each_value
        .filter_map { |v| normalize_registry_entry(v) }
        .select do |entry|
          family = entry[:tokenizer_family].to_s.strip.downcase.tr("-", "_").to_sym
          %i[hf_tokenizers huggingface_tokenizers tokenizers].include?(family)
        end
        .map { |entry| entry[:tokenizer_path].to_s }
        .map(&:strip)
        .reject(&:empty?)
        .uniq
    rescue StandardError
      []
    end

    def resolve_registry_entry(model_hint)
      return nil unless @registry

      key = model_hint.to_s
      return nil if key.empty?

      entry =
        if @registry.respond_to?(:lookup)
          @registry.lookup(key)
        elsif @registry.respond_to?(:call)
          @registry.call(key)
        elsif @registry.is_a?(Hash)
          @registry[key] || fnmatch_hash_entry(@registry, key)
        end

      normalize_registry_entry(entry)
    rescue StandardError
      nil
    end

    def fnmatch_hash_entry(hash, model_hint)
      hash.each do |pattern, value|
        p = pattern.to_s
        next unless p.include?("*") || p.include?("?") || p.include?("[")
        next unless File.fnmatch?(p, model_hint)

        return value
      rescue StandardError
        next
      end

      nil
    end

    def normalize_registry_entry(entry)
      case entry
      when nil
        nil
      when Hash
        entry.each_with_object({}) do |(k, v), out|
          out[k.to_s.strip.downcase.tr("-", "_").to_sym] = v
        end
      else
        nil
      end
    end
  end
end
