# frozen_string_literal: true

require_relative "util"

module LogicaRb
  Plan = Data.define(
    :schema,
    :engine,
    :final_predicates,
    :outputs,
    :preambles,
    :dependency_edges,
    :data_dependency_edges,
    :iterations,
    :config
  ) do
    self::TYPE_ORDER = {
      "data" => 0,
      "intermediate" => 1,
      "final" => 2,
    }.freeze

    def to_h
      {
        "schema" => schema,
        "engine" => engine,
        "final_predicates" => final_predicates,
        "outputs" => normalize_outputs(outputs, final_predicates),
        "preambles" => normalize_preambles(preambles),
        "dependency_edges" => normalize_edges(dependency_edges),
        "data_dependency_edges" => normalize_edges(data_dependency_edges),
        "iterations" => normalize_iterations(iterations),
        "config" => normalize_config(config),
      }
    end

    def to_json(pretty: true)
      self.class.json_dump(to_h, pretty: pretty)
    end

    def self.json_dump(obj, pretty: true)
      LogicaRb::Util.json_dump(obj, pretty: pretty)
    end

    private

    def normalize_outputs(outputs, final_predicates)
      list = outputs || []
      list = list.map { |o| o.respond_to?(:to_h) ? o.to_h : o }
      list = list.map { |o| stringify_keys(o) }

      if list.empty?
        final_predicates.map { |p| { "predicate" => p, "node" => p, "kind" => "table" } }
      else
        list
      end
    end

    def normalize_preambles(preambles)
      seen = {}
      Array(preambles).each do |preamble|
        text = preamble.to_s
        next if text.strip.empty?
        next if seen.key?(text)

        seen[text] = true
      end
      seen.keys
    end

    def normalize_edges(edges)
      set = {}
      Array(edges).each do |edge|
        next unless edge.is_a?(Array) && edge.length == 2
        a, b = edge
        set[[a.to_s, b.to_s]] = true
      end
      set.keys.sort_by { |(a, b)| [a, b] }
    end

    def normalize_iterations(iterations)
      result = {}
      (iterations || {}).each do |name, spec|
        spec_hash = spec.respond_to?(:to_h) ? spec.to_h : spec.dup
        spec_hash = stringify_keys(spec_hash)

        spec_hash["predicates"] = Array(spec_hash["predicates"]).map(&:to_s)
        spec_hash["stop_signal"] = spec_hash["stop_signal"].to_s

        result[name.to_s] = LogicaRb::Util.deep_copy(spec_hash)
      end
      result
    end

    def normalize_config(config)
      list = Array(config).map { |entry| normalize_node(entry) }
      list.sort_by do |row|
        [self.class::TYPE_ORDER.fetch(row["type"], 9), row["name"]]
      end
    end

    def normalize_node(entry)
      entry_hash = entry.respond_to?(:to_h) ? entry.to_h : entry.dup
      entry_hash = stringify_keys(entry_hash)

      entry_hash["name"] = entry_hash["name"].to_s
      entry_hash["type"] = entry_hash["type"].to_s

      requires = Array(entry_hash["requires"]).map(&:to_s)
      entry_hash["requires"] = requires.uniq.sort

      action = entry_hash["action"]
      action_hash =
        if action.is_a?(Plan::Action)
          action.to_h
        elsif action.respond_to?(:to_h)
          stringify_keys(action.to_h)
        else
          stringify_keys(action || {})
        end
      entry_hash["action"] = action_hash

      entry_hash
    end

    def stringify_keys(hash)
      hash.each_with_object({}) do |(key, value), result|
        result[key.to_s] = value
      end
    end
  end

  Plan::Node = Data.define(:name, :type, :requires, :action) do
    def to_h
      {
        "name" => name,
        "type" => type,
        "requires" => Array(requires).map(&:to_s).uniq.sort,
        "action" => action.respond_to?(:to_h) ? action.to_h : action,
      }
    end
  end

  Plan::Action = Data.define(:predicate, :launcher, :engine, :sql) do
    def to_h
      result = { "predicate" => predicate, "launcher" => launcher }
      result["engine"] = engine if engine
      result["sql"] = sql if sql
      result
    end
  end
end
