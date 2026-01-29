# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      module Packs
        # Built-in macro pack aiming for SillyTavern parity (Wave 3).
        #
        # This file intentionally starts small and grows with tests. Avoid adding
        # macros without a corresponding spec/characterization test.
        module SillyTavern
          def self.default_registry
            @default_registry ||= begin
              registry = TavernKit::SillyTavern::Macro::Registry.new
              register(registry)
              registry
            end
          end

          def self.register(registry)
            register_time_macros(registry)
            registry
          end

          def self.register_time_macros(registry)
            # {{time_UTC::+3}} -> "HH:MM" (24h)
            registry.register("time_UTC") do |inv|
              offset = extract_hours_offset(inv)
              now = inv.now.utc.getlocal(offset * 3600)
              now.strftime("%H:%M")
            rescue StandardError
              ""
            end
          end

          def self.extract_hours_offset(inv)
            raw =
              if inv.args.is_a?(Array)
                inv.args.first
              else
                inv.args
              end

            Integer(raw.to_s.strip)
          rescue StandardError
            0
          end

          private_class_method :register_time_macros, :extract_hours_offset
        end
      end
    end
  end
end
