# frozen_string_literal: true

require "set"

require_relative "errors"

module LogicaRb
  class PlanValidator
    SUPPORTED_ENGINES = %w[sqlite psql].freeze
    SUPPORTED_NODE_TYPES = %w[data intermediate final].freeze
    SUPPORTED_LAUNCHERS = %w[none query].freeze
    SUPPORTED_OUTPUT_KINDS = %w[table].freeze

    def self.validate!(plan_hash)
      unless plan_hash.is_a?(Hash)
        raise PlanValidationError, "plan must be an object"
      end

      schema = plan_hash["schema"]
      unless schema == "logica_rb.plan.v1"
        raise PlanValidationError, "schema must be \"logica_rb.plan.v1\""
      end

      engine = plan_hash["engine"]
      unless SUPPORTED_ENGINES.include?(engine)
        raise PlanValidationError, "engine must be one of #{SUPPORTED_ENGINES.inspect}"
      end

      final_predicates = fetch_array_of_non_empty_strings(plan_hash, "final_predicates")

      outputs = plan_hash["outputs"]
      unless outputs.is_a?(Array)
        raise PlanValidationError, "outputs must be an array"
      end
      if outputs.length != final_predicates.length
        raise PlanValidationError, "outputs length must match final_predicates length"
      end

      outputs.each_with_index do |out, idx|
        unless out.is_a?(Hash)
          raise PlanValidationError, "outputs[#{idx}] must be an object"
        end
        unless out.keys.sort == %w[kind node predicate]
          raise PlanValidationError, "outputs[#{idx}] must have keys: predicate, node, kind"
        end
        predicate = out["predicate"]
        node = out["node"]
        kind = out["kind"]

        unless predicate.is_a?(String) && !predicate.empty?
          raise PlanValidationError, "outputs[#{idx}].predicate must be a non-empty string"
        end
        unless predicate == final_predicates[idx]
          raise PlanValidationError, "outputs[#{idx}].predicate must equal final_predicates[#{idx}]"
        end
        unless node.is_a?(String) && !node.empty?
          raise PlanValidationError, "outputs[#{idx}].node must be a non-empty string"
        end
        unless SUPPORTED_OUTPUT_KINDS.include?(kind)
          raise PlanValidationError, "outputs[#{idx}].kind must be one of #{SUPPORTED_OUTPUT_KINDS.inspect}"
        end
      end

      fetch_array_of_strings(plan_hash, "preambles")
      validate_edges!(plan_hash["dependency_edges"], "dependency_edges")
      validate_edges!(plan_hash["data_dependency_edges"], "data_dependency_edges")

      iterations = plan_hash["iterations"]
      unless iterations.is_a?(Hash)
        raise PlanValidationError, "iterations must be an object"
      end

      config = plan_hash["config"]
      unless config.is_a?(Array)
        raise PlanValidationError, "config must be an array"
      end

      nodes_by_name = {}
      config.each_with_index do |entry, idx|
        unless entry.is_a?(Hash)
          raise PlanValidationError, "config[#{idx}] must be an object"
        end

        name = entry["name"]
        unless name.is_a?(String) && !name.empty?
          raise PlanValidationError, "config[#{idx}].name must be a non-empty string"
        end
        if nodes_by_name.key?(name)
          raise PlanValidationError, "config.name must be unique: #{name}"
        end

        type = entry["type"]
        unless SUPPORTED_NODE_TYPES.include?(type)
          raise PlanValidationError, "config[#{idx}].type must be one of #{SUPPORTED_NODE_TYPES.inspect}"
        end

        requires = entry["requires"]
        unless requires.is_a?(Array) && requires.all? { |r| r.is_a?(String) && !r.empty? }
          raise PlanValidationError, "config[#{idx}].requires must be an array of non-empty strings"
        end

        action = entry["action"]
        unless action.is_a?(Hash)
          raise PlanValidationError, "config[#{idx}].action must be an object"
        end

        action_predicate = action["predicate"]
        unless action_predicate.is_a?(String) && !action_predicate.empty?
          raise PlanValidationError, "config[#{idx}].action.predicate must be a non-empty string"
        end
        unless action_predicate == name
          raise PlanValidationError, "config[#{idx}].action.predicate must equal config[#{idx}].name"
        end

        launcher = action["launcher"]
        unless SUPPORTED_LAUNCHERS.include?(launcher)
          raise PlanValidationError, "config[#{idx}].action.launcher must be one of #{SUPPORTED_LAUNCHERS.inspect}"
        end

        case launcher
        when "none"
          # data node; no further requirements.
        when "query"
          action_engine = action["engine"]
          unless SUPPORTED_ENGINES.include?(action_engine)
            raise PlanValidationError, "config[#{idx}].action.engine must be one of #{SUPPORTED_ENGINES.inspect}"
          end
          sql = action["sql"]
          unless sql.is_a?(String)
            raise PlanValidationError, "config[#{idx}].action.sql must be a string"
          end
        end

        nodes_by_name[name] = entry
      end

      # requires closure
      nodes_by_name.each do |name, node|
        node.fetch("requires").each do |dep|
          next if nodes_by_name.key?(dep)
          raise PlanValidationError, "node #{name} requires missing dependency: #{dep}"
        end
      end

      # outputs closure
      outputs.each do |out|
        node = out.fetch("node")
        next if nodes_by_name.key?(node)
        raise PlanValidationError, "outputs references missing node: #{node}"
      end

      # iterations membership and basic legality
      member_of_iter = {}
      iterations.each do |iter_name, spec|
        unless spec.is_a?(Hash)
          raise PlanValidationError, "iterations.#{iter_name} must be an object"
        end

        predicates = spec["predicates"]
        unless predicates.is_a?(Array) && predicates.all? { |p| p.is_a?(String) && !p.empty? }
          raise PlanValidationError, "iterations.#{iter_name}.predicates must be an array of non-empty strings"
        end

        repetitions = spec["repetitions"]
        unless repetitions.is_a?(Integer) && repetitions >= 0
          raise PlanValidationError, "iterations.#{iter_name}.repetitions must be an integer >= 0"
        end

        stop_signal = spec["stop_signal"]
        unless stop_signal.is_a?(String)
          raise PlanValidationError, "iterations.#{iter_name}.stop_signal must be a string"
        end

        predicates.each do |predicate|
          unless nodes_by_name.key?(predicate)
            raise PlanValidationError, "iterations.#{iter_name} references missing node: #{predicate}"
          end

          launcher = nodes_by_name.dig(predicate, "action", "launcher")
          unless launcher == "query"
            raise PlanValidationError, "iterations.#{iter_name} node must have launcher=query: #{predicate}"
          end

          if member_of_iter.key?(predicate)
            raise PlanValidationError, "node appears in multiple iterations: #{predicate}"
          end
          member_of_iter[predicate] = iter_name
        end
      end

      validate_no_cycles!(nodes_by_name, iterations, member_of_iter)

      true
    end

    def self.fetch_array_of_strings(hash, key)
      value = hash[key]
      unless value.is_a?(Array) && value.all? { |v| v.is_a?(String) }
        raise PlanValidationError, "#{key} must be an array of strings"
      end
      value
    end

    def self.fetch_array_of_non_empty_strings(hash, key)
      value = hash[key]
      unless value.is_a?(Array) && value.all? { |v| v.is_a?(String) && !v.empty? }
        raise PlanValidationError, "#{key} must be an array of non-empty strings"
      end
      value
    end

    def self.validate_edges!(edges, label)
      unless edges.is_a?(Array)
        raise PlanValidationError, "#{label} must be an array"
      end

      edges.each_with_index do |edge, idx|
        unless edge.is_a?(Array) && edge.length == 2 && edge.all? { |v| v.is_a?(String) && !v.empty? }
          raise PlanValidationError, "#{label}[#{idx}] must be [String, String]"
        end
      end
    end

    def self.validate_no_cycles!(nodes_by_name, iterations, member_of_iter)
      units = Set.new
      units.merge(nodes_by_name.keys)
      units.merge(iterations.keys.map { |name| "iter:#{name}" })

      unit_deps = Hash.new { |h, k| h[k] = Set.new }

      # Non-iterative node dependencies.
      nodes_by_name.each do |name, node|
        next if member_of_iter.key?(name)
        node.fetch("requires").each do |dep|
          if member_of_iter.key?(dep)
            unit_deps[name].add("iter:#{member_of_iter.fetch(dep)}")
          else
            unit_deps[name].add(dep)
          end
        end
      end

      # Iteration group dependencies (macro-node).
      iterations.each do |iter_name, spec|
        unit = "iter:#{iter_name}"
        members = spec.fetch("predicates")
        members_set = members.to_set
        members.each do |member|
          nodes_by_name.fetch(member).fetch("requires").each do |dep|
            next if members_set.include?(dep)

            if member_of_iter.key?(dep)
              unit_deps[unit].add("iter:#{member_of_iter.fetch(dep)}")
            else
              unit_deps[unit].add(dep)
            end
          end
        end
      end

      # Kahn's algorithm
      indegree = units.to_h { |u| [u, 0] }
      unit_deps.each do |u, deps|
        deps.each do |dep|
          next unless indegree.key?(u)
          indegree[u] += 1 if units.include?(dep)
        end
      end

      ready = indegree.select { |_u, deg| deg.zero? }.map(&:first)
      processed = 0

      adjacency = Hash.new { |h, k| h[k] = [] }
      unit_deps.each do |u, deps|
        deps.each do |dep|
          next unless units.include?(dep)
          adjacency[dep] << u
        end
      end

      until ready.empty?
        current = ready.shift
        processed += 1
        adjacency[current].each do |neighbor|
          indegree[neighbor] -= 1
          ready << neighbor if indegree[neighbor].zero?
        end
      end

      return if processed == units.length

      remaining = indegree.select { |_u, deg| deg.positive? }.keys.sort
      raise PlanValidationError, "plan has a cycle or deadlock among: #{remaining.join(', ')}"
    end
  end
end
