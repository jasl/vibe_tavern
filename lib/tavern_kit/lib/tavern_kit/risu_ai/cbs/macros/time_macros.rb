# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      module Macros
        module_function

        MONTH_LONG = %w[January February March April May June July August September October November December].freeze
        MONTH_SHORT = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze
        WEEKDAY_LONG = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
        WEEKDAY_SHORT = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

        def resolve_date(args)
          if args.empty?
            now = Time.now
            return "#{now.year}-#{now.month}-#{now.day}"
          end

          format = args[0].to_s
          timestamp_seconds = parse_timestamp_seconds(args[1])
          date_time_format(format, timestamp_seconds: timestamp_seconds)
        end
        private_class_method :resolve_date

        def resolve_time(args)
          if args.empty?
            now = Time.now
            return "#{now.hour}:#{now.min}:#{now.sec}"
          end

          format = args[0].to_s
          timestamp_seconds = parse_timestamp_seconds(args[1])
          date_time_format(format, timestamp_seconds: timestamp_seconds)
        end
        private_class_method :resolve_time

        def resolve_unixtime
          # Upstream: (Date.now()/1000).toFixed(0) => rounded seconds.
          Time.now.to_f.round.to_s
        end
        private_class_method :resolve_unixtime

        def resolve_isotime
          t = Time.now.utc
          "#{t.hour}:#{t.min}:#{t.sec}"
        end
        private_class_method :resolve_isotime

        def resolve_isodate
          t = Time.now.utc
          "#{t.year}-#{t.month}-#{t.day}"
        end
        private_class_method :resolve_isodate

        def parse_timestamp_seconds(value)
          return 0.0 if value.nil? || value.to_s.empty?

          t = js_number(value) / 1000.0
          t.nan? ? 0.0 : t
        end
        private_class_method :parse_timestamp_seconds

        def date_time_format(format, timestamp_seconds:)
          f = format.to_s
          return "" if f.empty?

          # Upstream strips leading ":".
          f = f.delete_prefix(":") if f.start_with?(":")

          # Guardrail: avoid huge accidental inputs.
          return "" if f.length > 300

          t =
            if timestamp_seconds.to_f == 0.0
              Time.now
            else
              Time.at(timestamp_seconds.to_f)
            end

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
        end
        private_class_method :date_time_format
      end
    end
  end
end
