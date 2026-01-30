# frozen_string_literal: true

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
          end

          private_class_method :register_time_macros
        end
      end
    end
  end
end
