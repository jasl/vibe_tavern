# frozen_string_literal: true

module LogicaRb
  module SqlSafety
    module ForbiddenFunctionsValidator
      def self.validate!(sql, engine: nil, forbidden_functions: nil)
        sql = sql.to_s
        engine = engine.to_s
        engine = nil if engine.empty?

        cleaned = LogicaRb::SqlSafety::QueryOnlyValidator.strip_comments_and_strings(sql)

        forbidden_functions_set =
          if forbidden_functions.nil?
            LogicaRb::SqlSafety::QueryOnlyValidator.forbidden_functions_for_engine(engine)
          else
            LogicaRb::SqlSafety::QueryOnlyValidator.normalize_forbidden_functions(forbidden_functions)
          end

        hit = LogicaRb::SqlSafety::QueryOnlyValidator.first_forbidden_function_call(cleaned, forbidden_functions_set)
        return nil unless hit

        raise LogicaRb::SqlSafety::Violation.new(:forbidden_function, "Disallowed SQL function: #{hit}")
      end
    end
  end
end
