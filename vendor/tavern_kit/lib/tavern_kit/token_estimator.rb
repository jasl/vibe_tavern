# frozen_string_literal: true

require "tiktoken_ruby"

module TavernKit
  # Token counting utility with a pluggable adapter interface.
  class TokenEstimator
    module Adapter
      class Base
        def estimate(text, model_hint: nil) = raise NotImplementedError

        def describe(model_hint: nil) = { backend: self.class.name }
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
      @fallback_heuristic = Adapter::Heuristic.new
    end

    def estimate(text, model_hint: nil)
      resolve_adapter(model_hint).estimate(text, model_hint: model_hint)
    rescue StandardError
      begin
        @fallback_heuristic.estimate(text, model_hint: model_hint)
      rescue StandardError
        0
      end
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
        (entry[:tokenizer_family] || entry[:family] || entry[:backend])
          .to_s
          .strip
          .downcase
          .tr("-", "_")
          .to_sym

      case family
      when :heuristic
        chars_per_token = entry[:chars_per_token] || entry[:cpt]
        chars_per_token = Adapter::Heuristic::DEFAULT_CHARS_PER_TOKEN if chars_per_token.nil?

        key =
          begin
            Float(chars_per_token)
          rescue ArgumentError, TypeError
            Adapter::Heuristic::DEFAULT_CHARS_PER_TOKEN
          end

        @heuristics[key] ||= Adapter::Heuristic.new(chars_per_token: key)
      else
        @adapter
      end
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
