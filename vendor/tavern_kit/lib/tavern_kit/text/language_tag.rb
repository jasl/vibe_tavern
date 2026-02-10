# frozen_string_literal: true

module TavernKit
  module Text
    # Minimal, syntax-level BCP-47 / RFC 5646 language tag utilities.
    #
    # This module intentionally does NOT implement allowlists or product policy.
    # It only:
    # - validates the tag shape (best-effort, syntax-level)
    # - normalizes casing conventions (primary lower, script TitleCase, region upper)
    module LanguageTag
      module_function

      # Normalize a language tag to a canonical casing form.
      #
      # Returns nil when the tag is not a valid BCP-47-ish syntax.
      def normalize(value)
        raw = value.to_s.strip
        return nil if raw.empty?

        tag = raw.tr("_", "-")
        return nil unless valid_syntax?(tag)

        parts = tag.split("-")
        out = []

        out << parts.shift.to_s.downcase

        if parts.first&.match?(/\A[A-Za-z]{4}\z/)
          script = parts.shift.to_s
          out << script[0].to_s.upcase + script[1..].to_s.downcase
        end

        if parts.first&.match?(/\A[A-Za-z]{2}\z/)
          out << parts.shift.to_s.upcase
        elsif parts.first&.match?(/\A\d{3}\z/)
          out << parts.shift.to_s
        end

        parts.each { |p| out << p.to_s.downcase }

        out.join("-")
      rescue StandardError
        nil
      end

      def valid?(value)
        !normalize(value).nil?
      end

      def valid_syntax?(value)
        s = value.to_s.strip
        return false if s.empty?
        return false unless s.match?(/\A[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z/)

        parts = s.split("-")
        primary = parts.shift.to_s
        return false unless primary.match?(/\A[A-Za-z]{2,8}\z/)

        idx = 0

        # optional script
        idx += 1 if parts[idx]&.match?(/\A[A-Za-z]{4}\z/)
        # optional region
        idx += 1 if parts[idx]&.match?(/\A(?:[A-Za-z]{2}|\d{3})\z/)

        # variants
        while parts[idx] && (parts[idx].match?(/\A\d[A-Za-z0-9]{3}\z/) || parts[idx].match?(/\A[A-Za-z0-9]{5,8}\z/))
          idx += 1
        end

        # extensions (best-effort)
        while parts[idx] && parts[idx].match?(/\A[0-9A-WY-Za-wy-z]\z/)
          idx += 1
          return false unless parts[idx] && parts[idx].match?(/\A[A-Za-z0-9]{2,8}\z/)

          idx += 1
          idx += 1 while parts[idx] && parts[idx].match?(/\A[A-Za-z0-9]{2,8}\z/)
        end

        # private use
        if parts[idx]&.match?(/\A[xX]\z/)
          idx += 1
          return false unless parts[idx] && parts[idx].match?(/\A[A-Za-z0-9]{1,8}\z/)

          idx += 1
          idx += 1 while parts[idx] && parts[idx].match?(/\A[A-Za-z0-9]{1,8}\z/)
        end

        idx == parts.length
      rescue StandardError
        false
      end

      private_class_method :valid_syntax?
    end
  end
end
