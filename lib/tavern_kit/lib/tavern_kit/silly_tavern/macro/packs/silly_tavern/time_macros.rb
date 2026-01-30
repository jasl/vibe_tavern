# frozen_string_literal: true

require "time"

module TavernKit
  module SillyTavern
    module Macro
      module Packs
        module SillyTavern
          def self.register_time_macros(registry)
            # {{time}} or {{time::UTC+2}}
            registry.register(
              "time",
              unnamed_args: [
                { name: "offset", optional: true, type: :string },
              ],
            ) do |inv|
              raw = Array(inv.args).first
              return inv.now.strftime("%-I:%M %p") if raw.nil? || raw.to_s.strip.empty?

              match = raw.to_s.strip.match(/\AUTC(?<hours>[+-]\d+)\z/i)
              return inv.now.strftime("%-I:%M %p") unless match

              offset_hours = Integer(match[:hours])
              inv.now.utc.getlocal(offset_hours * 3600).strftime("%-I:%M %p")
            rescue StandardError
              ""
            end

            registry.register("date") { |inv| inv.now.strftime("%B %-d, %Y") }
            registry.register("weekday") { |inv| inv.now.strftime("%A") }
            registry.register("isotime") { |inv| inv.now.strftime("%H:%M") }
            registry.register("isodate") { |inv| inv.now.strftime("%Y-%m-%d") }

            registry.register(
              "datetimeformat",
              unnamed_args: [
                { name: "format", type: :string },
              ],
            ) do |inv|
              format = Array(inv.args).first.to_s
              next "" if format.strip.empty?

              inv.now.strftime(moment_to_strftime(format))
            rescue StandardError
              ""
            end

            registry.register("idleDuration") { |inv| idle_duration(inv) }
            registry.register_alias("idleDuration", "idle_duration", visible: false)

            registry.register(
              "timeDiff",
              unnamed_args: [
                { name: "left", type: :string },
                { name: "right", type: :string },
              ],
            ) do |inv|
              left, right = Array(inv.args)
              lt = coerce_time(left)
              rt = coerce_time(right)
              next "" if lt.nil? || rt.nil?

              humanize_seconds(lt - rt, with_suffix: true)
            end
          end

          def self.idle_duration(inv)
            env = inv.environment
            attrs = env.respond_to?(:platform_attrs) ? env.platform_attrs : {}
            chat = attrs["chat"] || attrs["messages"]
            return "just now" unless chat.is_a?(Array) && !chat.empty?

            last = nil
            take_next = false

            chat.reverse_each do |message|
              h = message.is_a?(Hash) ? message : {}
              ha = TavernKit::Utils::HashAccessor.wrap(h)

              next if ha.bool(:is_system, :isSystem, default: false)

              if ha.bool(:is_user, :isUser, default: false) && take_next
                last = h
                break
              end

              take_next = true
            end

            return "just now" if last.nil?

            send_date = TavernKit::Utils::HashAccessor.wrap(last).fetch(:send_date, :sendDate, default: nil)
            return "just now" if send_date.nil?

            ts = coerce_time(send_date)
            return "just now" if ts.nil?

            humanize_seconds(inv.now - ts)
          rescue StandardError
            "just now"
          end

          def self.coerce_time(value)
            return value if value.is_a?(Time)

            if value.is_a?(Integer)
              # Heuristic: treat 13+ digit values as ms timestamps.
              return Time.at(value >= 1_000_000_000_000 ? value / 1000.0 : value)
            end

            s = value.to_s.strip
            return nil if s.empty?

            if s.match?(/\A\d+\z/)
              i = s.to_i
              return Time.at(i >= 1_000_000_000_000 ? i / 1000.0 : i)
            end

            Time.parse(s)
          rescue StandardError
            nil
          end

          def self.humanize_seconds(seconds, with_suffix: false)
            value = seconds.to_f
            abs = value.abs

            phrase =
              if abs < 45
                "a few seconds"
              elsif abs < 90
                "a minute"
              elsif abs < 45 * 60
                "#{(abs / 60.0).round} minutes"
              elsif abs < 90 * 60
                "an hour"
              elsif abs < 22 * 3600
                "#{(abs / 3600.0).round} hours"
              elsif abs < 36 * 3600
                "a day"
              elsif abs < 26 * 86_400
                "#{(abs / 86_400.0).round} days"
              elsif abs < 45 * 86_400
                "a month"
              elsif abs < 320 * 86_400
                "#{(abs / 2_592_000.0).round} months"
              else
                "#{(abs / 31_536_000.0).round} years"
              end

            return phrase unless with_suffix

            return "in #{phrase}" if value.positive?
            return "#{phrase} ago" if value.negative?

            phrase
          end

          MOMENT_TOKEN_MAP = {
            "YYYY" => "%Y",
            "YY" => "%y",
            "MMMM" => "%B",
            "MMM" => "%b",
            "MM" => "%m",
            "DD" => "%d",
            "dddd" => "%A",
            "ddd" => "%a",
            "HH" => "%H",
            "hh" => "%I",
            "mm" => "%M",
            "ss" => "%S",
          }.freeze

          def self.moment_to_strftime(format)
            out = format.to_s.dup
            # Replace longer tokens first to avoid partial matches.
            MOMENT_TOKEN_MAP.sort_by { |k, _v| -k.length }.each do |token, strftime|
              out = out.gsub(token, strftime)
            end
            out
          end

          private_class_method :register_time_macros, :idle_duration, :coerce_time, :humanize_seconds, :moment_to_strftime
        end
      end
    end
  end
end
