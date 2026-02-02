# frozen_string_literal: true

module LogicaRb
  module Rails
    module EngineDetector
      def self.detect(connection)
        adapter_name =
          if connection.respond_to?(:adapter_name)
            connection.adapter_name.to_s
          else
            connection.to_s
          end

        return "sqlite" if adapter_name.match?(/sqlite/i)
        return "psql" if adapter_name.match?(/postg/i)

        raise LogicaRb::UnsupportedEngineError, adapter_name
      end
    end
  end
end
