# frozen_string_literal: true

require_relative "util"
require_relative "errors"

module LogicaRb
  Compilation = Data.define(
    :schema_version,
    :engine,
    :final_predicates,
    :outputs,
    :query_sql_by_predicate,
    :script_sql_by_predicate,
    :plan_by_predicate,
    :analysis,
    :metadata
  ) do
    def sql(predicate_or_format = nil, format = :script)
      predicate = predicate_or_format

      if format == :script && %w[query script].include?(predicate.to_s)
        format = predicate
        predicate = nil
      end

      if predicate.nil?
        return LogicaRb::Util.join_outputs(final_predicates.map { |p| sql(p, format) })
      end

      predicate = predicate.to_s
      by_predicate =
        case format.to_s
        when "query"
          query_sql_by_predicate
        when "script"
          script_sql_by_predicate
        else
          raise InvalidFormatError, "Unknown format: #{format}"
        end

      by_predicate.fetch(predicate)
    rescue KeyError
      raise ArgumentError, "Unknown predicate: #{predicate}"
    end

    def plan(predicate = nil)
      if predicate.nil?
        return nil if plan_by_predicate.nil? || plan_by_predicate.empty?
        return plan_by_predicate.values.first if plan_by_predicate.length == 1
        unique = plan_by_predicate.values.uniq
        return unique.first if unique.length == 1

        raise ArgumentError, "Predicate must be provided when multiple different plans exist."
      end

      plan_by_predicate.fetch(predicate.to_s)
    end

    def plan_json(predicate = nil, pretty: true)
      p = plan(predicate)
      return nil unless p
      p.to_json(pretty: pretty)
    end

    def to_h
      {
        "schema_version" => schema_version,
        "engine" => engine,
        "final_predicates" => final_predicates,
        "outputs" => outputs,
        "query_sql_by_predicate" => query_sql_by_predicate,
        "script_sql_by_predicate" => script_sql_by_predicate,
        "plan_by_predicate" => plan_by_predicate&.transform_values { |p| p&.to_h },
        "analysis" => analysis,
        "metadata" => metadata,
      }
    end

    def to_json(pretty: true)
      self.class.json_dump(to_h, pretty: pretty)
    end

    def self.json_dump(obj, pretty: true)
      LogicaRb::Util.json_dump(obj, pretty: pretty)
    end
  end
end
