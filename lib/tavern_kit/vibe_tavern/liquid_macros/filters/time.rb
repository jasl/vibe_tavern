# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module LiquidMacros
      module Filters
        # Time/date helpers for prompts.
        #
        # We intentionally keep the API small and predictable. For fully custom
        # formatting, prefer Liquid's built-in `date` filter with an app-injected
        # `Time` value.
        #
        # For porting RisuAI-style templates, we also provide a Moment-ish token
        # formatter (`datetimeformat`) compatible with a common subset.
        module Time
          MONTH_LONG = %w[January February March April May June July August September October November December].freeze
          MONTH_SHORT = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze
          WEEKDAY_LONG = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
          WEEKDAY_SHORT = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

          # Liquid filter: `{{ context.now_ms | unixtime }}`
          #
          # - input: epoch milliseconds (preferred) or seconds
          # - output: rounded epoch seconds (string)
          def unixtime(input = nil)
            t = time_from_ms_or_now(input)
            t.to_f.round.to_s
          rescue StandardError
            ""
          end

          # Liquid filter: `{{ context.now_ms | isodate }}`
          #
          # Returns an ISO-like date in UTC: "YYYY-M-D" (no zero padding).
          def isodate(input = nil)
            t = time_from_ms_or_now(input).utc
            "#{t.year}-#{t.month}-#{t.day}"
          rescue StandardError
            ""
          end

          # Liquid filter: `{{ context.now_ms | isotime }}`
          #
          # Returns an ISO-like time in UTC: "H:M:S" (no zero padding).
          def isotime(input = nil)
            t = time_from_ms_or_now(input).utc
            "#{t.hour}:#{t.min}:#{t.sec}"
          rescue StandardError
            ""
          end

          # Liquid filter: `{{ context.now_ms | datetimeformat: \"YYYY-MM-DD HH:mm:ss\" }}`
          #
          # Moment-ish tokens supported (subset):
          # - YYYY, YY
          # - MMMM, MMM, MM
          # - DDDD, DD
          # - dddd, ddd
          # - HH, hh, mm, ss
          # - X (seconds), x (milliseconds)
          # - A (AM/PM)
          #
          # Notes:
          # - Leading ":" is ignored (RisuAI compatibility).
          # - Formatting happens in UTC to avoid environment-dependent output.
          def datetimeformat(input = nil, format = nil)
            f = format.to_s
            return "" if f.empty?

            f = f.delete_prefix(":") if f.start_with?(":")
            return "" if f.length > 300

            t = time_from_ms_or_now(input).utc

            hour12 = t.hour % 12
            hour12 = 12 if hour12.zero?

            f
              .gsub("YYYY", t.year.to_s)
              .gsub("YY", t.year.to_s[-2, 2].to_s)
              .gsub("MMMM", MONTH_LONG[t.month - 1])
              .gsub("MMM", MONTH_SHORT[t.month - 1])
              .gsub("MM", t.month.to_s.rjust(2, "0"))
              .gsub("DDDD", t.yday.to_s)
              .gsub("DD", t.day.to_s.rjust(2, "0"))
              .gsub("dddd", WEEKDAY_LONG[t.wday])
              .gsub("ddd", WEEKDAY_SHORT[t.wday])
              .gsub("HH", t.hour.to_s.rjust(2, "0"))
              .gsub("hh", hour12.to_s.rjust(2, "0"))
              .gsub("mm", t.min.to_s.rjust(2, "0"))
              .gsub("ss", t.sec.to_s.rjust(2, "0"))
              .gsub("X", t.to_i.to_s)
              .gsub("x", (t.to_f * 1000).floor.to_i.to_s)
              .gsub("A", t.hour >= 12 ? "PM" : "AM")
          rescue StandardError
            ""
          end

          private

          def time_from_ms_or_now(input)
            if input.nil? || input.to_s.strip.empty? || input.to_s == "0"
              ms = context_now_ms
              return ::Time.now if ms.nil?

              return time_from_ms(ms)
            end

            time_from_ms(input)
          end

          def time_from_ms(value)
            f = Float(value.to_s.strip)

            # Heuristic: treat values >= 10^11 as milliseconds, else seconds.
            seconds = f >= 100_000_000_000 ? (f / 1000.0) : f
            ::Time.at(seconds)
          rescue ArgumentError, TypeError
            ::Time.now
          end

          def context_now_ms
            context = @context&.registers&.[](:context)
            if context.respond_to?(:[])
              return context[:now_ms] if context[:now_ms]
            end

            raw = @context&.[]("context")
            return raw["now_ms"] if raw.is_a?(Hash) && raw.key?("now_ms")

            nil
          end
        end
      end
    end
  end
end
