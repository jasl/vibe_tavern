# frozen_string_literal: true

require "set"

module LogicaRb
  module SqlSafety
    module QueryOnlyValidator
      BASE_FORBIDDEN_KEYWORDS = Set.new(
        %w[
          INSERT UPDATE DELETE MERGE CREATE DROP ALTER TRUNCATE GRANT REVOKE
          BEGIN COMMIT ROLLBACK SET RESET
          VACUUM ANALYZE REINDEX
        ]
      ).freeze

      SQLITE_FORBIDDEN_KEYWORDS = Set.new(%w[ATTACH DETACH PRAGMA]).freeze
      PSQL_FORBIDDEN_KEYWORDS = Set.new(%w[COPY DO CALL]).freeze

      SQLITE_FORBIDDEN_FUNCTIONS = Set.new(%w[load_extension readfile writefile]).freeze
      PSQL_FORBIDDEN_FUNCTIONS = Set.new(
        %w[
          pg_read_file pg_read_binary_file pg_ls_dir pg_stat_file
          lo_import lo_export
          pg_sleep pg_sleep_for pg_sleep_until
          pg_cancel_backend pg_terminate_backend pg_reload_conf
          dblink dblink_connect dblink_connect_u
          set_config
        ]
      ).freeze

      WORD_TOKEN = /[A-Za-z_][A-Za-z0-9_]*/.freeze

      FUNCTION_TOKEN_REGEX = /
        "(?:[^"]|"")*" |         # double-quoted identifier
        `(?:[^`]|``)*` |         # backtick-quoted identifier
        \[(?:[^\]]|\]\])*\] |    # bracket-quoted identifier
        [A-Za-z_][A-Za-z0-9_]* | # bare identifier
        [().]                    # punctuation
      /x.freeze

      def self.validate!(sql, engine: nil, allow_explain: false, forbidden_functions: nil)
        sql = sql.to_s
        engine = engine.to_s
        engine = nil if engine.empty?

        cleaned = strip_comments_and_literals(sql)
        validate_semicolons!(cleaned)

        tokens = cleaned.scan(WORD_TOKEN).map!(&:upcase)
        if tokens.empty?
          raise LogicaRb::SqlSafety::Violation.new(:empty_sql, "SQL must be a non-empty query")
        end

        first = tokens.first
        allowed_first = %w[SELECT WITH VALUES]
        allowed_first << "EXPLAIN" if allow_explain

        unless allowed_first.include?(first)
          raise LogicaRb::SqlSafety::Violation.new(:not_a_query, "Only SELECT/WITH/VALUES queries are allowed")
        end

        forbidden = forbidden_keywords_for_engine(engine)
        hit = tokens.find { |t| forbidden.include?(t) }
        if hit
          raise LogicaRb::SqlSafety::Violation.new(:forbidden_keyword, "Disallowed SQL keyword: #{hit}")
        end

        forbidden_functions_set =
          if forbidden_functions.nil?
            forbidden_functions_for_engine(engine)
          else
            normalize_forbidden_functions(forbidden_functions)
          end

        cleaned_for_function_scan = strip_comments_and_strings(sql)
        hit_function = first_forbidden_function_call(cleaned_for_function_scan, forbidden_functions_set)
        if hit_function
          raise LogicaRb::SqlSafety::Violation.new(:forbidden_function, "Disallowed SQL function: #{hit_function}")
        end

        if (engine.nil? || engine == "psql") && tokens.include?("INTO")
          raise LogicaRb::SqlSafety::Violation.new(:select_into, "PostgreSQL SELECT INTO is not allowed")
        end

        nil
      end

      def self.validate_semicolons!(cleaned)
        trimmed = cleaned.rstrip
        trimmed = trimmed.chomp(";").rstrip if trimmed.end_with?(";")
        return nil unless trimmed.include?(";")

        raise LogicaRb::SqlSafety::Violation.new(:multiple_statements, "Multiple SQL statements are not allowed")
      end

      def self.forbidden_keywords_for_engine(engine)
        keywords = BASE_FORBIDDEN_KEYWORDS.dup

        case engine
        when "sqlite"
          keywords.merge(SQLITE_FORBIDDEN_KEYWORDS)
        when "psql"
          keywords.merge(PSQL_FORBIDDEN_KEYWORDS)
        else
          keywords.merge(SQLITE_FORBIDDEN_KEYWORDS)
          keywords.merge(PSQL_FORBIDDEN_KEYWORDS)
        end

        keywords
      end

      def self.forbidden_functions_for_engine(engine)
        funcs = Set.new

        case engine
        when "sqlite"
          funcs.merge(SQLITE_FORBIDDEN_FUNCTIONS)
        when "psql"
          funcs.merge(PSQL_FORBIDDEN_FUNCTIONS)
        else
          funcs.merge(SQLITE_FORBIDDEN_FUNCTIONS)
          funcs.merge(PSQL_FORBIDDEN_FUNCTIONS)
        end

        funcs
      end

      def self.normalize_forbidden_functions(value)
        list = value.is_a?(Set) ? value.to_a : Array(value)

        list
          .compact
          .map(&:to_s)
          .map(&:strip)
          .reject(&:empty?)
          .map(&:downcase)
          .to_set
      end

      def self.first_forbidden_function_call(cleaned_sql, forbidden_functions_set)
        return nil if forbidden_functions_set.empty?

        tokens = cleaned_sql.scan(FUNCTION_TOKEN_REGEX)
        tokens.each_with_index do |tok, idx|
          next unless tokens[idx + 1] == "("

          name = normalize_identifier_token(tok)
          next if name.nil?
          next unless forbidden_functions_set.include?(name)

          return name
        end

        nil
      end

      def self.normalize_identifier_token(tok)
        return nil if tok.nil? || tok.empty?

        if tok.start_with?("\"") && tok.end_with?("\"") && tok.length >= 2
          raw = tok[1..-2].gsub("\"\"", "\"")
          return raw.strip.downcase
        end

        if tok.start_with?("`") && tok.end_with?("`") && tok.length >= 2
          raw = tok[1..-2].gsub("``", "`")
          return raw.strip.downcase
        end

        if tok.start_with?("[") && tok.end_with?("]") && tok.length >= 2
          raw = tok[1..-2].gsub("]]", "]")
          return raw.strip.downcase
        end

        return nil unless WORD_TOKEN.match?(tok)

        tok.downcase
      end
      private_class_method :normalize_identifier_token

      def self.strip_comments_and_literals(sql)
        s = sql.dup
        s = s.b

        i = 0
        while i < s.bytesize
          b = s.getbyte(i)
          nb = s.getbyte(i + 1)

          if b == 45 && nb == 45 # "--"
            s.setbyte(i, 32)
            s.setbyte(i + 1, 32)
            i += 2
            while i < s.bytesize
              c = s.getbyte(i)
              break if c == 10 # "\n"
              s.setbyte(i, 32)
              i += 1
            end
            next
          end

          if b == 47 && nb == 42 # "/*"
            depth = 1
            s.setbyte(i, 32)
            s.setbyte(i + 1, 32)
            i += 2
            while i < s.bytesize && depth.positive?
              c = s.getbyte(i)
              cn = s.getbyte(i + 1)

              if c == 47 && cn == 42 # "/*"
                s.setbyte(i, 32)
                s.setbyte(i + 1, 32)
                i += 2
                depth += 1
                next
              end

              if c == 42 && cn == 47 # "*/"
                s.setbyte(i, 32)
                s.setbyte(i + 1, 32)
                i += 2
                depth -= 1
                next
              end

              s.setbyte(i, 32) unless c == 10 # keep newlines
              i += 1
            end
            next
          end

          if b == 39 # "'"
            s.setbyte(i, 32)
            i += 1
            while i < s.bytesize
              c = s.getbyte(i)
              cn = s.getbyte(i + 1)

              if c == 39 # "'"
                if cn == 39 # "''"
                  s.setbyte(i, 32)
                  s.setbyte(i + 1, 32)
                  i += 2
                  next
                end

                s.setbyte(i, 32)
                i += 1
                break
              end

              s.setbyte(i, 32) unless c == 10
              i += 1
            end
            next
          end

          if b == 34 # "\""
            s.setbyte(i, 32)
            i += 1
            while i < s.bytesize
              c = s.getbyte(i)
              cn = s.getbyte(i + 1)

              if c == 34
                if cn == 34 # "\"\""
                  s.setbyte(i, 32)
                  s.setbyte(i + 1, 32)
                  i += 2
                  next
                end

                s.setbyte(i, 32)
                i += 1
                break
              end

              s.setbyte(i, 32) unless c == 10
              i += 1
            end
            next
          end

          if b == 96 # "`"
            s.setbyte(i, 32)
            i += 1
            while i < s.bytesize
              c = s.getbyte(i)
              cn = s.getbyte(i + 1)

              if c == 96
                if cn == 96 # "``"
                  s.setbyte(i, 32)
                  s.setbyte(i + 1, 32)
                  i += 2
                  next
                end

                s.setbyte(i, 32)
                i += 1
                break
              end

              s.setbyte(i, 32) unless c == 10
              i += 1
            end
            next
          end

          if b == 91 # "["
            s.setbyte(i, 32)
            i += 1
            while i < s.bytesize
              c = s.getbyte(i)
              cn = s.getbyte(i + 1)

              if c == 93 # "]"
                if cn == 93 # "]]"
                  s.setbyte(i, 32)
                  s.setbyte(i + 1, 32)
                  i += 2
                  next
                end

                s.setbyte(i, 32)
                i += 1
                break
              end

              s.setbyte(i, 32) unless c == 10
              i += 1
            end
            next
          end

          if b == 36 # "$"
            tag_end = i + 1
            while tag_end < s.bytesize
              c = s.getbyte(tag_end)
              break if c == 36
              break unless (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95

              tag_end += 1
            end

            if tag_end < s.bytesize && s.getbyte(tag_end) == 36
              delim = s.byteslice(i, tag_end - i + 1)
              (i..tag_end).each { |idx| s.setbyte(idx, 32) }

              search_from = tag_end + 1
              close_idx = s.index(delim, search_from)

              if close_idx
                (search_from...close_idx).each do |idx|
                  s.setbyte(idx, 32) unless s.getbyte(idx) == 10
                end
                (close_idx...(close_idx + delim.bytesize)).each { |idx| s.setbyte(idx, 32) }
                i = close_idx + delim.bytesize
                next
              end

              (search_from...s.bytesize).each do |idx|
                s.setbyte(idx, 32) unless s.getbyte(idx) == 10
              end
              break
            end
          end

          i += 1
        end

        s.force_encoding(sql.encoding)
      end

      def self.strip_comments_and_strings(sql)
        s = sql.dup
        s = s.b

        i = 0
        while i < s.bytesize
          b = s.getbyte(i)
          nb = s.getbyte(i + 1)

          if b == 34 # "\""
            i += 1
            while i < s.bytesize
              c = s.getbyte(i)
              cn = s.getbyte(i + 1)

              if c == 34
                if cn == 34 # "\"\""
                  i += 2
                  next
                end

                i += 1
                break
              end

              i += 1
            end
            next
          end

          if b == 96 # "`"
            i += 1
            while i < s.bytesize
              c = s.getbyte(i)
              cn = s.getbyte(i + 1)

              if c == 96
                if cn == 96 # "``"
                  i += 2
                  next
                end

                i += 1
                break
              end

              i += 1
            end
            next
          end

          if b == 91 # "["
            i += 1
            while i < s.bytesize
              c = s.getbyte(i)
              cn = s.getbyte(i + 1)

              if c == 93 # "]"
                if cn == 93 # "]]"
                  i += 2
                  next
                end

                i += 1
                break
              end

              i += 1
            end
            next
          end

          if b == 45 && nb == 45 # "--"
            s.setbyte(i, 32)
            s.setbyte(i + 1, 32)
            i += 2
            while i < s.bytesize
              c = s.getbyte(i)
              break if c == 10 # "\n"
              s.setbyte(i, 32)
              i += 1
            end
            next
          end

          if b == 47 && nb == 42 # "/*"
            depth = 1
            s.setbyte(i, 32)
            s.setbyte(i + 1, 32)
            i += 2
            while i < s.bytesize && depth.positive?
              c = s.getbyte(i)
              cn = s.getbyte(i + 1)

              if c == 47 && cn == 42 # "/*"
                s.setbyte(i, 32)
                s.setbyte(i + 1, 32)
                i += 2
                depth += 1
                next
              end

              if c == 42 && cn == 47 # "*/"
                s.setbyte(i, 32)
                s.setbyte(i + 1, 32)
                i += 2
                depth -= 1
                next
              end

              s.setbyte(i, 32) unless c == 10 # keep newlines
              i += 1
            end
            next
          end

          if b == 39 # "'"
            s.setbyte(i, 32)
            i += 1
            while i < s.bytesize
              c = s.getbyte(i)
              cn = s.getbyte(i + 1)

              if c == 39 # "'"
                if cn == 39 # "''"
                  s.setbyte(i, 32)
                  s.setbyte(i + 1, 32)
                  i += 2
                  next
                end

                s.setbyte(i, 32)
                i += 1
                break
              end

              s.setbyte(i, 32) unless c == 10
              i += 1
            end
            next
          end

          if b == 36 # "$"
            tag_end = i + 1
            while tag_end < s.bytesize
              c = s.getbyte(tag_end)
              break if c == 36
              break unless (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95

              tag_end += 1
            end

            if tag_end < s.bytesize && s.getbyte(tag_end) == 36
              delim = s.byteslice(i, tag_end - i + 1)
              (i..tag_end).each { |idx| s.setbyte(idx, 32) }

              search_from = tag_end + 1
              close_idx = s.index(delim, search_from)

              if close_idx
                (search_from...close_idx).each do |idx|
                  s.setbyte(idx, 32) unless s.getbyte(idx) == 10
                end
                (close_idx...(close_idx + delim.bytesize)).each { |idx| s.setbyte(idx, 32) }
                i = close_idx + delim.bytesize
                next
              end

              (search_from...s.bytesize).each do |idx|
                s.setbyte(idx, 32) unless s.getbyte(idx) == 10
              end
              break
            end
          end

          i += 1
        end

        s.force_encoding(sql.encoding)
      end
    end
  end
end
