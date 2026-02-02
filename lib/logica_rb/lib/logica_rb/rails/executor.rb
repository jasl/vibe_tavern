# frozen_string_literal: true

module LogicaRb
  module Rails
    class Executor
      DEFAULT_QUERY_NAME = "LogicaRb".freeze

      def initialize(connection:)
        @connection = connection
      end

      def select_all(sql, access_policy: nil)
        raw = @connection.respond_to?(:raw_connection) ? @connection.raw_connection : nil

        if defined?(::SQLite3::Database) && raw.is_a?(::SQLite3::Database) && access_policy&.trust == :untrusted
          # Untrusted execution is hardened at the connection level (e.g. PRAGMA query_only/trusted_schema)
          # and via a restrictive SQLite authorizer (defense in depth).
          LogicaRb::SqliteSafety::Authorizer.with_authorizer(
            raw,
            capabilities: access_policy.effective_capabilities,
            access_policy: access_policy,
            harden: true
          ) do
            @connection.select_all(sql)
          end
        else
          @connection.select_all(sql)
        end
      end

      def exec_query(sql, name: DEFAULT_QUERY_NAME, binds: [], prepare: false)
        @connection.exec_query(sql, name, binds, prepare: prepare)
      end

      def exec_script(sql_script)
        sql_script = sql_script.to_s

        raw = @connection.respond_to?(:raw_connection) ? @connection.raw_connection : nil

        if defined?(::SQLite3::Database) && raw.is_a?(::SQLite3::Database)
          raw.execute_batch(sql_script)
        elsif defined?(::PG::Connection) && raw.is_a?(::PG::Connection)
          raw.exec(sql_script)
        else
          @connection.execute(sql_script)
        end
      end
    end
  end
end
