# frozen_string_literal: true

module TavernKit
  class PromptBuilder
    # Application-owned per-run context.
    #
    # This holds runtime input and per-step module configuration overrides.
    # It is intentionally simple and immutable-by-convention.
    class Context
      attr_reader :type, :id, :module_configs

      def self.build(raw, **kwargs)
        new(normalize(raw, **kwargs), **kwargs)
      end

      def self.normalize(raw, **_kwargs)
        return raw.to_h if raw.is_a?(self)

        normalize_hash_keys(raw)
      end

      def self.normalize_hash_keys(raw)
        h = raw.is_a?(Hash) ? raw : {}

        h.each_with_object({}) do |(key, value), out|
          underscored = TavernKit::Utils.underscore(key)
          next if underscored.strip.empty?

          out[underscored.to_sym] = value
        end
      end
      private_class_method :normalize_hash_keys

      def initialize(data = {}, type: nil, id: nil, module_configs: nil, **kwargs)
        @type = type&.to_sym
        @id = id&.to_s

        merged_data = data.is_a?(Hash) ? data.dup : {}
        merged_data.merge!(kwargs) if kwargs.any?
        @data = self.class.normalize(merged_data)

        embedded_configs = @data.delete(:module_configs)
        configs = module_configs.nil? ? embedded_configs : module_configs
        configs ||= {}
        @module_configs = normalize_module_configs(configs)
      end

      def to_h
        @data.dup
      end

      def [](key)
        @data[key.to_sym]
      end

      def []=(key, value)
        @data[key.to_sym] = value
      end

      def fetch(key, default = nil, &block)
        @data.fetch(key.to_sym, default, &block)
      end

      def key?(key)
        @data.key?(key.to_sym)
      end

      def runtime
        raw = @data[:runtime]
        return raw if raw.nil? || raw.is_a?(TavernKit::PromptBuilder::Context)
        return raw unless raw.is_a?(Hash)

        normalized = TavernKit::PromptBuilder::Context.build(raw, type: :app)
        @data[:runtime] = normalized
        normalized
      end

      def runtime=(value)
        @data[:runtime] =
          if value.is_a?(Hash)
            TavernKit::PromptBuilder::Context.build(value, type: :app)
          else
            value
          end
      end

      def method_missing(name, *args)
        method_name = name.to_s
        if method_name.end_with?("=")
          key = method_name.delete_suffix("=").to_sym
          @data[key] = args.first
          return args.first
        end

        return @data[name] if args.empty? && @data.key?(name)

        super
      end

      def respond_to_missing?(name, include_private = false)
        key = name.to_s.delete_suffix("=").to_sym
        @data.key?(key) || super
      end

      private

      def normalize_module_configs(value)
        return {} if value.nil?
        raise ArgumentError, "module_configs must be a Hash" unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, cfg), out|
          step_name = key.to_s.strip.downcase.tr("-", "_").to_sym
          raise ArgumentError, "module_configs.#{key} must be a Hash" unless cfg.is_a?(Hash)

          cfg.each_key do |cfg_key|
            unless cfg_key.is_a?(Symbol)
              raise ArgumentError, "module_configs.#{key} keys must be Symbols (got #{cfg_key.class})"
            end
          end

          out[step_name] = cfg.dup
        end
      end
    end
  end
end
