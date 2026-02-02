# frozen_string_literal: true

require "set"

module LogicaRb
  module SqliteSafety
    module Authorizer
      SQLITE_OK = 0
      SQLITE_DENY = 1

      ACTION_PRAGMA = 19
      ACTION_READ = 20
      ACTION_SELECT = 21
      ACTION_FUNCTION = 31

      SAFE_VIRTUAL_TABLES = Set.new(%w[json_each json_tree]).freeze
      FORBIDDEN_FUNCTIONS = Set.new(%w[load_extension readfile writefile]).freeze

      # Enables a restrictive SQLite authorizer for untrusted query execution.
      #
      # This is intentionally a defense-in-depth mechanism (in addition to SQL validation):
      # it blocks all actions by default, permitting only reads from allowlisted relations and a small
      # set of safe virtual tables.
      #
      # When `harden: true`, we also try to apply connection-level pragmas that further harden the session.
      # Some SQLite builds may not support these pragmas, so failures are rescued and we fall back to just
      # the authorizer (no hard crash).
      def self.with_authorizer(db, capabilities:, access_policy: nil, harden: true)
        policy = access_policy
        return yield unless policy&.trust == :untrusted

        denied = policy.effective_denied_schemas(engine: "sqlite").map(&:downcase).to_set
        allowed = policy.allowed_relations
        allowed_set = allowed.nil? ? nil : Array(allowed).map(&:to_s).map(&:strip).reject(&:empty?).map(&:downcase).to_set

        begin
          db.enable_load_extension(false) if db.respond_to?(:enable_load_extension)
        rescue StandardError
          # ignore
        end

        prev = db.instance_variable_get(:@authorizer)

        hardening_state = nil

        if harden
          begin
            # NOTE: These pragmas are executed before installing the authorizer because PRAGMA is denied by
            # default. We later allow *reading* these specific pragmas under the authorizer so tests (and
            # observability) can verify that hardening is active without allowing arbitrary PRAGMA usage.
            prev_query_only = db.get_first_value("PRAGMA query_only")
            prev_trusted_schema = db.get_first_value("PRAGMA trusted_schema")

            db.execute("PRAGMA query_only = 1")
            db.execute("PRAGMA trusted_schema = 0")

            hardening_state = {
              query_only: prev_query_only,
              trusted_schema: prev_trusted_schema,
            }
          rescue StandardError
            # Some SQLite versions/builds don't support these pragmas. Fall back to only the authorizer.
            # If we partially applied settings, best-effort revert (also rescued).
            begin
              previous_authorizer = prev
              db.authorizer = nil

              db.execute("PRAGMA query_only = #{Integer(prev_query_only)}") if defined?(prev_query_only) && !prev_query_only.nil?
              db.execute("PRAGMA trusted_schema = #{Integer(prev_trusted_schema)}") if defined?(prev_trusted_schema) && !prev_trusted_schema.nil?
            rescue StandardError
              # ignore
            ensure
              begin
                db.authorizer = previous_authorizer
              rescue StandardError
                # ignore
              end
            end

            hardening_state = nil
          end
        end

        db.authorizer = lambda do |action, arg1, arg2, dbname, _source|
          case action
          when ACTION_SELECT
            SQLITE_OK
          when ACTION_FUNCTION
            name = arg2.to_s.downcase
            FORBIDDEN_FUNCTIONS.include?(name) ? SQLITE_DENY : SQLITE_OK
          when ACTION_PRAGMA
            pragma = arg1.to_s.downcase
            # Allow reading these two hardening pragmas for verification/observability.
            return SQLITE_OK if %w[query_only trusted_schema].include?(pragma) && arg2.nil?

            SQLITE_DENY
          when ACTION_READ
            table = arg1.to_s.downcase
            schema = dbname.to_s.downcase

            return SQLITE_DENY if denied.include?(schema) || denied.include?(table)
            return SQLITE_OK if SAFE_VIRTUAL_TABLES.include?(table)
            return SQLITE_DENY if allowed_set.nil? || allowed_set.empty?

            qualified = "#{schema}.#{table}"
            (allowed_set.include?(table) || allowed_set.include?(qualified)) ? SQLITE_OK : SQLITE_DENY
          else
            SQLITE_DENY
          end
        end

        yield
      ensure
        # Temporarily clear our authorizer for restoration PRAGMAs (PRAGMA is denied under the authorizer).
        begin
          db.authorizer = nil
        rescue StandardError
          # ignore
        end

        if hardening_state
          begin
            db.execute("PRAGMA query_only = #{Integer(hardening_state.fetch(:query_only))}")
            db.execute("PRAGMA trusted_schema = #{Integer(hardening_state.fetch(:trusted_schema))}")
          rescue StandardError
            # ignore
          end
        end

        begin
          db.authorizer = prev
        rescue StandardError
          # ignore
        end
      end

      # Backwards-compatible alias for older call sites.
      def self.with_untrusted_policy(db, access_policy, harden: true)
        with_authorizer(db, capabilities: access_policy&.effective_capabilities, access_policy: access_policy, harden: harden) do
          yield
        end
      end
    end
  end
end
