# frozen_string_literal: true

require "set"

module LogicaRb
  module SqlSafety
    module RelationAccessValidator
      CLAUSE_END_KEYWORDS = Set.new(
        %w[
          WHERE GROUP ORDER HAVING LIMIT OFFSET WINDOW FETCH UNION EXCEPT INTERSECT
        ]
      ).freeze

      TOKEN_REGEX = /
        "(?:[^"]|"")*" |          # double-quoted identifier
        `(?:[^`]|``)*` |          # backtick-quoted identifier
        \[(?:[^\]]|\]\])*\] |     # bracket-quoted identifier
        [A-Za-z_][A-Za-z0-9_$]* | # bare identifier or keyword
        [(),.]                    # punctuation
      /x.freeze

      def self.validate!(sql, engine:, allowed_relations: nil, allowed_schemas: nil, denied_schemas: nil)
        engine = engine.to_s
        sql = sql.to_s

        cleaned = LogicaRb::SqlSafety::QueryOnlyValidator.strip_comments_and_strings(sql)
        tokens = cleaned.scan(TOKEN_REGEX)

        cte_names = extract_cte_names(tokens)
        relations_used = Set.new

        denied = normalize_ident_list(denied_schemas)
        denied ||= LogicaRb::AccessPolicy.default_denied_schemas(engine)
        denied_set = denied.to_set

        allowed_relations_norm = normalize_ident_list(allowed_relations)
        allowed_schemas_norm = normalize_ident_list(allowed_schemas)

        default_schema = default_schema_for_engine(engine)

        paren_depth = 0
        in_from_at_depth = {}

        idx = 0
        while idx < tokens.length
          tok = tokens[idx]

          case tok
          when "("
            paren_depth += 1
            idx += 1
            next
          when ")"
            in_from_at_depth.delete(paren_depth)
            paren_depth -= 1 if paren_depth.positive?
            idx += 1
            next
          end

          up = tok_upcase(tok)

          if up == "FROM"
            in_from_at_depth[paren_depth] = true
            idx = parse_and_validate_relation(tokens, idx + 1, engine: engine, default_schema: default_schema, cte_names: cte_names,
                                                      denied_set: denied_set, allowed_relations: allowed_relations_norm, allowed_schemas: allowed_schemas_norm,
                                                      relations_used: relations_used)
            next
          end

          if up == "JOIN"
            in_from_at_depth[paren_depth] = true
            idx = parse_and_validate_relation(tokens, idx + 1, engine: engine, default_schema: default_schema, cte_names: cte_names,
                                                      denied_set: denied_set, allowed_relations: allowed_relations_norm, allowed_schemas: allowed_schemas_norm,
                                                      relations_used: relations_used)
            next
          end

          if tok == "," && in_from_at_depth[paren_depth]
            idx = parse_and_validate_relation(tokens, idx + 1, engine: engine, default_schema: default_schema, cte_names: cte_names,
                                                      denied_set: denied_set, allowed_relations: allowed_relations_norm, allowed_schemas: allowed_schemas_norm,
                                                      relations_used: relations_used)
            next
          end

          if in_from_at_depth[paren_depth] && CLAUSE_END_KEYWORDS.include?(up)
            in_from_at_depth[paren_depth] = false
          end

          idx += 1
        end

        relations_used.to_a.sort
      end

      def self.parse_and_validate_relation(tokens, idx, engine:, default_schema:, cte_names:, denied_set:, allowed_relations:, allowed_schemas:,
                                           relations_used:)
        idx = skip_join_noise(tokens, idx)
        return idx if idx >= tokens.length

        tok = tokens[idx]
        return idx if tok == "(" # subquery / derived table

        name1, idx = parse_identifier(tokens, idx)
        return idx unless name1

        return idx if idx < tokens.length && tokens[idx] == "(" # table-valued function

        schema = nil
        table = name1

        if idx < tokens.length && tokens[idx] == "."
          schema = name1
          name2, idx2 = parse_identifier(tokens, idx + 1)

          if name2.nil?
            raise LogicaRb::SqlSafety::Violation.new(:invalid_relation, "Invalid SQL relation reference after '.'")
          end

          table = name2
          idx = idx2
        end

        if schema.nil? && cte_names.include?(table)
          return idx
        end

        if engine == "psql" && schema.nil? && table.start_with?("pg_")
          raise LogicaRb::SqlSafety::Violation.new(
            :relation_not_allowed,
            "SQL relation access is not allowed: #{table}. " \
            "PostgreSQL always searches pg_catalog via search_path, so an unqualified pg_* name may resolve to a system " \
            "catalog relation (e.g. pg_catalog.#{table}). " \
            "Fix: use an explicit schema-qualified relation (e.g. public.#{table}) and allow it explicitly, " \
            "or rename the table."
          )
        end

        effective_schema = (schema || default_schema).to_s
        relations_used.add("#{effective_schema.downcase}.#{table.downcase}")

        if denied_set.include?(effective_schema) || denied_set.include?(table)
          raise LogicaRb::SqlSafety::Violation.new(
            :denied_schema,
            "Disallowed schema/table referenced in SQL: #{schema ? "#{schema}.#{table}" : table}"
          )
        end

        validate_allowed!(engine: engine, schema: effective_schema, table: table, allowed_relations: allowed_relations, allowed_schemas: allowed_schemas, original_schema: schema)

        idx
      end
      private_class_method :parse_and_validate_relation

      def self.scan_relations(sql, engine:)
        engine = engine.to_s
        sql = sql.to_s

        cleaned = LogicaRb::SqlSafety::QueryOnlyValidator.strip_comments_and_strings(sql)
        tokens = cleaned.scan(TOKEN_REGEX)
        cte_names = extract_cte_names(tokens)
        default_schema = default_schema_for_engine(engine)

        relations_used = Set.new

        paren_depth = 0
        in_from_at_depth = {}

        idx = 0
        while idx < tokens.length
          tok = tokens[idx]

          case tok
          when "("
            paren_depth += 1
            idx += 1
            next
          when ")"
            in_from_at_depth.delete(paren_depth)
            paren_depth -= 1 if paren_depth.positive?
            idx += 1
            next
          end

          up = tok_upcase(tok)

          if up == "FROM" || up == "JOIN" || (tok == "," && in_from_at_depth[paren_depth])
            in_from_at_depth[paren_depth] = true
            idx = scan_relation(tokens, idx + 1, default_schema: default_schema, cte_names: cte_names, relations_used: relations_used)
            next
          end

          in_from_at_depth[paren_depth] = false if in_from_at_depth[paren_depth] && CLAUSE_END_KEYWORDS.include?(up)

          idx += 1
        end

        relations_used.to_a.sort
      end

      def self.scan_relation(tokens, idx, default_schema:, cte_names:, relations_used:)
        idx = skip_join_noise(tokens, idx)
        return idx if idx >= tokens.length

        tok = tokens[idx]
        return idx if tok == "("

        name1, idx = parse_identifier(tokens, idx)
        return idx unless name1

        return idx if idx < tokens.length && tokens[idx] == "("

        schema = nil
        table = name1

        if idx < tokens.length && tokens[idx] == "."
          schema = name1
          name2, idx2 = parse_identifier(tokens, idx + 1)

          return idx2 if name2.nil?

          table = name2
          idx = idx2
        end

        return idx if schema.nil? && cte_names.include?(table)

        effective_schema = (schema || default_schema).to_s.downcase
        relations_used.add("#{effective_schema}.#{table.downcase}")
        idx
      end
      private_class_method :scan_relation

      def self.validate_allowed!(engine:, schema:, table:, allowed_relations:, allowed_schemas:, original_schema:)
        return nil if allowed_relations.nil? && allowed_schemas.nil?

        if !allowed_relations.nil?
          relation = original_schema ? "#{schema}.#{table}" : table
          qualified = "#{schema}.#{table}"

          if allowed_relations.empty?
            raise LogicaRb::SqlSafety::Violation.new(:relation_not_allowed, "SQL relation access is not allowed: #{relation}")
          end

          return nil if allowed_relations.include?(qualified)
          return nil if original_schema.nil? && allowed_relations.include?(table)

          raise LogicaRb::SqlSafety::Violation.new(:relation_not_allowed, "SQL relation access is not allowed: #{qualified}")
        end

        if allowed_schemas.empty?
          raise LogicaRb::SqlSafety::Violation.new(:schema_not_allowed, "SQL schema access is not allowed: #{schema}")
        end

        return nil if allowed_schemas.include?(schema)

        raise LogicaRb::SqlSafety::Violation.new(:schema_not_allowed, "SQL schema access is not allowed: #{schema}")
      end
      private_class_method :validate_allowed!

      def self.default_schema_for_engine(engine)
        case engine.to_s
        when "psql"
          "public"
        else
          "main"
        end
      end
      private_class_method :default_schema_for_engine

      def self.extract_cte_names(tokens)
        names = Set.new
        return names if tokens.empty?

        idx = 0
        return names unless tok_upcase(tokens[idx]) == "WITH"

        idx += 1
        idx += 1 if idx < tokens.length && tok_upcase(tokens[idx]) == "RECURSIVE"

        loop do
          name, idx = parse_identifier(tokens, idx)
          break unless name

          names.add(name)

          if idx < tokens.length && tokens[idx] == "("
            idx = skip_parenthesized(tokens, idx)
          end

          idx += 1 if idx < tokens.length && tok_upcase(tokens[idx]) == "AS"

          if idx < tokens.length && tokens[idx] == "("
            idx = skip_parenthesized(tokens, idx)
          end

          break unless idx < tokens.length && tokens[idx] == ","

          idx += 1
        end

        names
      end
      private_class_method :extract_cte_names

      def self.skip_parenthesized(tokens, idx)
        return idx unless tokens[idx] == "("

        depth = 0
        while idx < tokens.length
          tok = tokens[idx]
          depth += 1 if tok == "("
          depth -= 1 if tok == ")"
          idx += 1
          break if depth.zero?
        end

        idx
      end
      private_class_method :skip_parenthesized

      def self.skip_join_noise(tokens, idx)
        loop do
          return idx if idx >= tokens.length

          up = tok_upcase(tokens[idx])
          case up
          when "LATERAL", "ONLY", "AS", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "OUTER", "NATURAL"
            idx += 1
            next
          else
            return idx
          end
        end
      end
      private_class_method :skip_join_noise

      def self.parse_identifier(tokens, idx)
        return [nil, idx] if idx >= tokens.length

        tok = tokens[idx]
        if tok.start_with?("\"") && tok.end_with?("\"") && tok.length >= 2
          raw = tok[1..-2]
          raw = raw.gsub("\"\"", "\"")
          return [raw.strip.downcase, idx + 1]
        end

        if tok.start_with?("`") && tok.end_with?("`") && tok.length >= 2
          raw = tok[1..-2]
          raw = raw.gsub("``", "`")
          return [raw.strip.downcase, idx + 1]
        end

        if tok.start_with?("[") && tok.end_with?("]") && tok.length >= 2
          raw = tok[1..-2]
          raw = raw.gsub("]]", "]")
          return [raw.strip.downcase, idx + 1]
        end

        return [nil, idx] unless /\A[A-Za-z_][A-Za-z0-9_$]*\z/.match?(tok)

        [tok.downcase, idx + 1]
      end
      private_class_method :parse_identifier

      def self.normalize_ident_list(value)
        return nil if value.nil?

        Array(value)
          .compact
          .map(&:to_s)
          .map(&:strip)
          .reject(&:empty?)
          .map(&:downcase)
          .uniq
      end
      private_class_method :normalize_ident_list

      def self.tok_upcase(tok)
        return "" if tok.nil?
        return tok.upcase if /\A[A-Za-z_]/.match?(tok)

        ""
      end
      private_class_method :tok_upcase
    end
  end
end
