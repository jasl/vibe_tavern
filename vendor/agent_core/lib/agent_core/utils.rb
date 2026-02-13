# frozen_string_literal: true

module AgentCore
  module Utils
    module_function

    # Shallow-convert Hash keys to Symbols.
    #
    # Symbol keys take precedence over their String equivalents.
    #
    # @param value [Hash, nil]
    # @return [Hash]
    def symbolize_keys(value)
      return {} if value.nil?
      raise ArgumentError, "Expected Hash, got #{value.class}" unless value.is_a?(Hash)

      out = {}

      # Prefer symbol keys when both exist (e.g., :model and "model").
      value.each do |k, v|
        out[k] = v if k.is_a?(Symbol)
      end

      value.each do |k, v|
        next if k.is_a?(Symbol)

        if k.respond_to?(:to_sym)
          sym = k.to_sym
          out[sym] = v unless out.key?(sym)
        else
          out[k] = v
        end
      end

      out
    end
  end
end
