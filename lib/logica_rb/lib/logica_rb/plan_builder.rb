# frozen_string_literal: true

require "set"

require_relative "plan"
require_relative "util"

module LogicaRb
  class PlanBuilder
    def self.from_executions(executions, engine:, final_predicates: nil)
      final_predicates ||= executions.map(&:main_predicate)
      final_predicates = normalize_predicates(final_predicates)
      final_predicate_set = final_predicates.to_set

      table_to_export_map = {}
      dependency_edges = Set.new
      data_dependency_edges = Set.new
      iterations = {}
      preambles = []
      seen_preambles = Set.new

      executions.each do |execution|
        iterations.merge!(execution.iterations || {})
        p_table_to_export_map = execution.table_to_export_map.dup
        p_dependency_edges = execution.dependency_edges.map(&:dup).to_set
        p_data_dependency_edges = execution.data_dependency_edges.map(&:dup).to_set

        final_predicate_set.each do |p|
          next if execution.main_predicate == p
          next unless p_table_to_export_map.key?(p)

          p_table_to_export_map, p_dependency_edges, p_data_dependency_edges = rename_predicate(
            p_table_to_export_map,
            p_dependency_edges,
            p_data_dependency_edges,
            p,
            "down_#{p}"
          )
        end

        p_table_to_export_map.each do |predicate, sql|
          table_to_export_map[predicate] = execution.predicate_specific_preamble(execution.main_predicate) + sql
        end

        p_dependency_edges.each { |edge| dependency_edges.add(edge) }
        p_data_dependency_edges.each { |edge| data_dependency_edges.add(edge) }

        preamble = execution.preamble
        next if preamble.to_s.strip.empty?
        next if seen_preambles.include?(preamble)

        preambles << preamble
        seen_preambles.add(preamble)
      end

      node_name_set = build_node_name_set(table_to_export_map, dependency_edges, data_dependency_edges)
      outputs = build_outputs(final_predicates, node_name_set)
      final_node_set = outputs.map { |o| o.fetch("node") }.to_set

      config = concertina_config(
        table_to_export_map,
        dependency_edges,
        data_dependency_edges,
        final_node_set,
        engine
      )

      Plan.new(
        schema: "logica_rb.plan.v1",
        engine: engine,
        final_predicates: final_predicates,
        outputs: outputs,
        preambles: preambles,
        dependency_edges: sort_edges(dependency_edges),
        data_dependency_edges: sort_edges(data_dependency_edges),
        iterations: LogicaRb::Util.deep_copy(iterations),
        config: config
      )
    end

    def self.rename_predicate(table_to_export_map, dependency_edges, data_dependency_edges, from_name, to_name)
      new_table_to_export_map = {}
      table_to_export_map.each do |k, v|
        new_table_to_export_map[k == from_name ? to_name : k] = v
      end
      new_dependency_edges = dependency_edges.each_with_object(Set.new) do |(a, b), set|
        a = to_name if a == from_name
        b = to_name if b == from_name
        set.add([a, b])
      end
      new_data_dependency_edges = data_dependency_edges.each_with_object(Set.new) do |(a, b), set|
        a = to_name if a == from_name
        b = to_name if b == from_name
        set.add([a, b])
      end
      [new_table_to_export_map, new_dependency_edges, new_data_dependency_edges]
    end

    def self.concertina_config(table_to_export_map, dependency_edges, data_dependency_edges, final_node_set, engine)
      depends_on = Hash.new { |h, k| h[k] = Set.new }
      (dependency_edges | data_dependency_edges).each do |source, target|
        depends_on[target].add(source)
      end

      data = data_dependency_edges.map(&:first).to_set
      data.merge(dependency_edges.select { |source, _| !table_to_export_map.key?(source) }.map(&:first))

      result = []
      data.each do |predicate|
        result << Plan::Node.new(
          name: predicate,
          type: "data",
          requires: [],
          action: Plan::Action.new(predicate: predicate, launcher: "none", engine: nil, sql: nil)
        )
      end

      table_to_export_map.each do |predicate, sql|
        result << Plan::Node.new(
          name: predicate,
          type: final_node_set.include?(predicate) ? "final" : "intermediate",
          requires: depends_on[predicate].to_a.sort,
          action: Plan::Action.new(predicate: predicate, launcher: "query", engine: engine, sql: sql)
        )
      end

      result.sort_by do |entry|
        type = entry.respond_to?(:type) ? entry.type : entry["type"]
        name = entry.respond_to?(:name) ? entry.name : entry["name"]
        [Plan::TYPE_ORDER.fetch(type.to_s, 9), name.to_s]
      end
    end

    def self.sort_edges(edges)
      edges.to_a.sort_by { |(a, b)| [a.to_s, b.to_s] }
    end

    def self.normalize_predicates(predicates)
      list = predicates.is_a?(Array) ? predicates : [predicates]
      list = list.compact.map(&:to_s).reject(&:empty?)

      seen = {}
      list.each_with_object([]) do |p, result|
        next if seen.key?(p)
        seen[p] = true
        result << p
      end
    end

    def self.build_outputs(final_predicates, node_name_set)
      final_predicates.map do |predicate|
        down = "down_#{predicate}"
        node =
          if node_name_set.include?(predicate)
            predicate
          elsif node_name_set.include?(down)
            down
          else
            raise PlanValidationError, "output predicate is missing from plan: #{predicate}"
          end

        { "predicate" => predicate, "node" => node, "kind" => "table" }
      end
    end

    def self.build_node_name_set(table_to_export_map, dependency_edges, data_dependency_edges)
      data = data_dependency_edges.map(&:first).to_set
      data.merge(dependency_edges.select { |source, _| !table_to_export_map.key?(source) }.map(&:first))

      data | table_to_export_map.keys.to_set
    end
  end
end
