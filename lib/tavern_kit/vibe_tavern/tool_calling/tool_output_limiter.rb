# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolCalling
      module ToolOutputLimiter
        module_function

        DEFAULT_MAX_DEPTH = 20
        DEFAULT_MAX_NODES = 50_000
        DEFAULT_MAX_HASH_KEYS = 50_000
        DEFAULT_MAX_ARRAY_ITEMS = 50_000

        UNKNOWN_OBJECT_BYTES = 64

        def check(
          value,
          max_bytes:,
          max_depth: DEFAULT_MAX_DEPTH,
          max_nodes: DEFAULT_MAX_NODES,
          max_hash_keys: DEFAULT_MAX_HASH_KEYS,
          max_array_items: DEFAULT_MAX_ARRAY_ITEMS
        )
          max_bytes = Integer(max_bytes)
          raise ArgumentError, "max_bytes must be positive" if max_bytes <= 0

          state = { bytes: 0, nodes: 0, seen: {} }

          reason =
            estimate(
              value,
              depth: 0,
              state: state,
              max_bytes: max_bytes,
              max_depth: max_depth,
              max_nodes: max_nodes,
              max_hash_keys: max_hash_keys,
              max_array_items: max_array_items,
            )

          if reason
            { ok: false, reason: reason, estimated_bytes: state[:bytes], max_bytes: max_bytes }
          else
            { ok: true, reason: nil, estimated_bytes: state[:bytes], max_bytes: max_bytes }
          end
        rescue ArgumentError, TypeError => e
          { ok: false, reason: "INVALID_LIMIT: #{e.message}", estimated_bytes: nil, max_bytes: nil }
        end

        def estimate_bytes(**kwargs)
          result = check(**kwargs)
          return :too_large unless result.fetch(:ok)

          result.fetch(:estimated_bytes)
        end

        def estimate(
          value,
          depth:,
          state:,
          max_bytes:,
          max_depth:,
          max_nodes:,
          max_hash_keys:,
          max_array_items:
        )
          return "MAX_DEPTH" if depth > max_depth
          return "MAX_NODES" if state.fetch(:nodes) > max_nodes

          case value
          when nil
            state[:bytes] += 4
          when true, false
            state[:bytes] += 5
          when String
            bytes = value.bytesize
            return "STRING_TOO_LARGE" if bytes > max_bytes

            state[:bytes] += bytes
          when Symbol
            state[:bytes] += value.to_s.bytesize
          when Numeric
            state[:bytes] += value.to_s.bytesize
          when Hash
            return "MAX_HASH_KEYS" if value.size > max_hash_keys

            return nil if seen?(value, state)

            value.each do |k, v|
              state[:nodes] += 1
              return "MAX_NODES" if state[:nodes] > max_nodes

              reason =
                estimate(
                  k,
                  depth: depth + 1,
                  state: state,
                  max_bytes: max_bytes,
                  max_depth: max_depth,
                  max_nodes: max_nodes,
                  max_hash_keys: max_hash_keys,
                  max_array_items: max_array_items,
                )
              return reason if reason

              reason =
                estimate(
                  v,
                  depth: depth + 1,
                  state: state,
                  max_bytes: max_bytes,
                  max_depth: max_depth,
                  max_nodes: max_nodes,
                  max_hash_keys: max_hash_keys,
                  max_array_items: max_array_items,
                )
              return reason if reason

              return "MAX_BYTES" if state[:bytes] > max_bytes
            end
          when Array
            return "MAX_ARRAY_ITEMS" if value.size > max_array_items

            return nil if seen?(value, state)

            value.each do |item|
              state[:nodes] += 1
              return "MAX_NODES" if state[:nodes] > max_nodes

              reason =
                estimate(
                  item,
                  depth: depth + 1,
                  state: state,
                  max_bytes: max_bytes,
                  max_depth: max_depth,
                  max_nodes: max_nodes,
                  max_hash_keys: max_hash_keys,
                  max_array_items: max_array_items,
                )
              return reason if reason

              return "MAX_BYTES" if state[:bytes] > max_bytes
            end
          else
            state[:bytes] += UNKNOWN_OBJECT_BYTES
          end

          return "MAX_BYTES" if state[:bytes] > max_bytes

          nil
        end

        def seen?(value, state)
          return false unless value.respond_to?(:object_id)

          oid = value.object_id
          seen = state.fetch(:seen)
          return true if seen.key?(oid)

          seen[oid] = true
          false
        end
        private_class_method :seen?

        private_class_method :estimate
      end
    end
  end
end

