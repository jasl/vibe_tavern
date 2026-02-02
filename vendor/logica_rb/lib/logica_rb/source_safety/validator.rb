# frozen_string_literal: true

require "set"

module LogicaRb
  module SourceSafety
    module Validator
      FORBIDDEN_CALLS = {
        "SqlExpr" => :sql_expr,
        "ReadFile" => :file_io,
        "ReadJson" => :file_io,
        "WriteFile" => :file_io,
        "PrintToConsole" => :console,
        "RunClingo" => :external_exec,
        "RunClingoFile" => :external_exec,
        "Intelligence" => :external_exec,
      }.freeze

      def self.validate!(parsed_rules, engine:, trust: :untrusted, capabilities: [])
        trust = :untrusted if trust.nil?
        trust = trust.is_a?(String) ? trust.strip.to_sym : trust.to_sym
        return nil unless trust == :untrusted

        capabilities_set = normalize_capabilities(capabilities)

        validate_ground_annotations!(parsed_rules, capabilities_set: capabilities_set)

        each_call_predicate_name(parsed_rules) do |predicate_name|
          required = FORBIDDEN_CALLS[predicate_name]
          next unless required
          next if capabilities_set.include?(required)

          raise Violation.new(
            :forbidden_call,
            "Forbidden call in untrusted source: #{predicate_name} (enable capability #{required.inspect} to allow)",
            predicate_name: predicate_name
          )
        end

        nil
      end

      def self.validate_ground_annotations!(parsed_rules, capabilities_set:)
        return nil if capabilities_set.include?(:ground_declarations)

        each_rule_head_predicate_name(parsed_rules) do |predicate_name|
          next unless predicate_name == "@Ground"

          raise Violation.new(
            :forbidden_annotation,
            "Forbidden annotation in untrusted source: @Ground (enable capability :ground_declarations to allow)",
            predicate_name: "@Ground"
          )
        end

        nil
      end
      private_class_method :validate_ground_annotations!

      def self.normalize_capabilities(value)
        LogicaRb::AccessPolicy.normalize_capabilities(value).to_set
      end
      private_class_method :normalize_capabilities

      def self.each_call_predicate_name(obj, &block)
        return enum_for(:each_call_predicate_name, obj) unless block_given?

        case obj
        when Array
          obj.each { |v| each_call_predicate_name(v, &block) }
        when Hash
          call = obj["call"]
          if call.is_a?(Hash)
            predicate_name = call["predicate_name"]
            yield predicate_name if predicate_name.is_a?(String) && !predicate_name.empty?
          end

          predicate = obj["predicate"]
          if predicate.is_a?(Hash)
            predicate_name = predicate["predicate_name"]
            yield predicate_name if predicate_name.is_a?(String) && !predicate_name.empty?
          end

          obj.each_value { |v| each_call_predicate_name(v, &block) }
        end
      end
      private_class_method :each_call_predicate_name

      def self.each_rule_head_predicate_name(obj, &block)
        return enum_for(:each_rule_head_predicate_name, obj) unless block_given?

        case obj
        when Array
          obj.each { |v| each_rule_head_predicate_name(v, &block) }
        when Hash
          head = obj["head"]
          if head.is_a?(Hash)
            predicate_name = head["predicate_name"]
            yield predicate_name if predicate_name.is_a?(String) && !predicate_name.empty?
          end
        end
      end
      private_class_method :each_rule_head_predicate_name
    end
  end
end
