# frozen_string_literal: true

module AgentCore
  module Contrib
    module Utils
      module_function

      # Deep-merge many hashes.
      #
      # - Hash values are merged recursively.
      # - Arrays and scalar values are replaced by the right-hand side.
      # - Non-Hash inputs are treated as {}.
      def deep_merge_hashes(*hashes)
        hashes.reduce({}) do |acc, h|
          deep_merge_two(acc, h)
        end
      end

      def deep_merge_two(left, right)
        lhs = left.is_a?(Hash) ? left : {}
        rhs = right.is_a?(Hash) ? right : {}

        out = lhs.each_with_object({}) { |(k, v), merged| merged[k] = v }

        rhs.each do |key, value|
          if out[key].is_a?(Hash) && value.is_a?(Hash)
            out[key] = deep_merge_two(out[key], value)
          else
            out[key] = value
          end
        end

        out
      end
      private_class_method :deep_merge_two
    end
  end
end
