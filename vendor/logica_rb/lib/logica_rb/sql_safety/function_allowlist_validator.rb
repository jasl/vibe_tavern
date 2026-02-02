# frozen_string_literal: true

require "set"

module LogicaRb
  module SqlSafety
    module FunctionAllowlistValidator
      NON_FUNCTION_PAREN_KEYWORDS = Set.new(
        %w[
          from join where group order having limit offset window fetch union except intersect
          select with as on
          in exists over filter within values
          any all
        ]
      ).freeze

      WORD_TOKEN = /\A[A-Za-z_][A-Za-z0-9_$]*\z/.freeze

      TOKEN_REGEX = /
        "(?:[^"]|"")*" |           # double-quoted identifier
        `(?:[^`]|``)*` |           # backtick-quoted identifier
        \[(?:[^\]]|\]\])*\] |      # bracket-quoted identifier
        [A-Za-z_][A-Za-z0-9_$]* |  # bare identifier
        [().]                      # punctuation
      /x.freeze

      def self.validate!(sql, engine:, allowed_functions:, forbidden_functions: nil)
        sql = sql.to_s
        engine = engine.to_s
        engine = nil if engine.empty?

        allowlist = allowed_functions.nil? ? nil : normalize_allowlist(allowed_functions)

        cleaned = LogicaRb::SqlSafety::QueryOnlyValidator.strip_comments_and_strings(sql)
        calls = scan_function_calls_from_cleaned(cleaned)
        used = calls.map { |call| call.fetch(:unqualified) }.to_set

        if forbidden_functions
          forbidden_set = LogicaRb::SqlSafety::QueryOnlyValidator.normalize_forbidden_functions(forbidden_functions)
          forbidden_hit = calls.find { |call| forbidden_set.include?(call.fetch(:unqualified)) }
          if forbidden_hit
            hit = forbidden_hit.fetch(:unqualified)
            raise LogicaRb::SqlSafety::Violation.new(:forbidden_function, "Disallowed SQL function: #{hit}", details: hit)
          end
        end

        return used if allowlist.nil?

        calls.each do |call|
          qualified = call.fetch(:qualified)
          unqualified = call.fetch(:unqualified)
          next if allowlist.include?(unqualified) || allowlist.include?(qualified)

          raise LogicaRb::SqlSafety::Violation.new(
            :function_not_allowed,
            "SQL function is not allowed: #{unqualified}",
            details: {
              function: unqualified,
              allowed: allowlist.to_a.sort,
              profile: infer_profile_from_allowlist(allowlist),
            }
          )
        end

        used
      end

      def self.scan_functions(sql)
        cleaned = LogicaRb::SqlSafety::QueryOnlyValidator.strip_comments_and_strings(sql.to_s)
        scan_functions_from_cleaned(cleaned)
      end

      def self.scan_functions_from_cleaned(cleaned_sql)
        calls = scan_function_calls_from_cleaned(cleaned_sql)
        seen = {}
        calls.each_with_object([]) do |call, result|
          name = call.fetch(:unqualified)
          next if seen[name]

          seen[name] = true
          result << name
        end
      end
      private_class_method :scan_functions_from_cleaned

      def self.scan_function_calls_from_cleaned(cleaned_sql)
        tokens = cleaned_sql.to_s.scan(TOKEN_REGEX)

        calls = []
        seen = {}

        tokens.each_index do |idx|
          next unless tokens[idx + 1] == "("

          qualified = normalize_qualified_identifier(tokens, idx)
          next if qualified.nil?
          next if !qualified.include?(".") && NON_FUNCTION_PAREN_KEYWORDS.include?(qualified)
          next if seen[qualified]

          unqualified = qualified.split(".").last
          seen[qualified] = true
          calls << { qualified: qualified, unqualified: unqualified }
        end

        calls
      end
      private_class_method :scan_function_calls_from_cleaned

      def self.normalize_allowlist(value)
        list = value.is_a?(Set) ? value.to_a : Array(value)

        list
          .compact
          .map { |v| normalize_qualified_identifier_string(v) }
          .compact
          .uniq
          .to_set
      end
      private_class_method :normalize_allowlist

      def self.normalize_qualified_identifier(tokens, idx)
        name = normalize_identifier_token(tokens[idx])
        return nil if name.nil?

        parts = [name]

        j = idx - 1
        while j >= 1 && tokens[j] == "."
          prefix = normalize_identifier_token(tokens[j - 1])
          break if prefix.nil?

          parts.unshift(prefix)
          j -= 2
        end

        parts.join(".")
      end
      private_class_method :normalize_qualified_identifier

      def self.normalize_qualified_identifier_string(value)
        s = value.to_s.strip
        return nil if s.empty?

        parts = s.split(".").map(&:strip)
        norm = parts.map { |part| normalize_identifier_text(part) }
        return nil if norm.any?(&:nil?)

        norm.join(".")
      end
      private_class_method :normalize_qualified_identifier_string

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

      def self.normalize_identifier_text(text)
        tok = text.to_s.strip
        return nil if tok.empty?

        normalize_identifier_token(tok)
      end
      private_class_method :normalize_identifier_text

      def self.infer_profile_from_allowlist(allowlist)
        minimal = LogicaRb::AccessPolicy::RAILS_MINIMAL_ALLOWED_FUNCTIONS
        minimal_plus = LogicaRb::AccessPolicy::RAILS_MINIMAL_PLUS_ALLOWED_FUNCTIONS

        return :rails_minimal if allowlist == minimal
        return :rails_minimal_plus if allowlist == minimal_plus

        :custom
      end
      private_class_method :infer_profile_from_allowlist
    end
  end
end
