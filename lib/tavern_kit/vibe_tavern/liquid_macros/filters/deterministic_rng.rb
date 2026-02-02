# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module LiquidMacros
      module Filters
        # Deterministic RNG helpers inspired by RisuAI's CBS macros.
        #
        # These are intended for prompt-building use (reproducible by default),
        # with seeds injected via runtime.
        module DeterministicRng
          # Liquid filter: `{{ "word" | hash7 }}`
          #
          # Returns a 7-digit deterministic number string derived from the input.
          def hash7(input)
            word = input.to_s
            num = (pick_hash_rand(0, word) * 10_000_000) + 1
            num.round.to_i.to_s.rjust(7, "0")
          rescue StandardError
            ""
          end

          # Liquid filter: `{{ "a,b,c" | pick }}`
          #
          # Picks a deterministic element from:
          # - an Array input, or
          # - a String split by `,` or `:` (supports escaping commas via `\\,`)
          #
          # Seeds:
          # - cid defaults to `runtime.message_index` (or 0)
          # - word defaults to `runtime.rng_word`, else `char`, else "0"
          #
          # Optional overrides:
          #   `{{ list | pick: 10, "seed" }}`
          def pick(input, cid = nil, word = nil)
            runtime = runtime_hash_from_context
            cid ||= (runtime && runtime["message_index"]) || 0
            word ||= (runtime && runtime["rng_word"])

            word = default_rng_word(word)

            rand = pick_hash_rand(cid.to_i, word.to_s)
            arr = normalize_pick_input(input)
            return "" if arr.empty?

            index = (rand * arr.length).floor
            element = arr[index]

            if element.is_a?(String)
              element.gsub("§X", ",")
            else
              ::JSON.generate(element) || ""
            end
          rescue StandardError
            ""
          end

          # Liquid filter: `{{ "2d6" | rollp }}`
          #
          # Deterministic dice roll using runtime seeds (RisuAI-like).
          # - notation: "NdM" or "M"
          # - uses `message_index` as base cid and `rng_word` as seed word
          def rollp(input, cid = nil, word = nil)
            notation = input.to_s.split("d")

            num = 1.0
            sides = 6.0

            if notation.length == 2
              num = notation[0].to_s.empty? ? 1.0 : Float(notation[0])
              sides = notation[1].to_s.empty? ? 6.0 : Float(notation[1])
            elsif notation.length == 1
              sides = Float(notation[0])
            end

            return "NaN" if num.nan? || sides.nan?
            return "NaN" if num < 1 || sides < 1

            runtime = runtime_hash_from_context
            cid ||= (runtime && runtime["message_index"]) || 0
            word ||= (runtime && runtime["rng_word"])
            word = default_rng_word(word)

            total = 0
            count = num.ceil
            base = cid.to_i

            count.times do |i|
              step_cid = base + (i * 15)
              rand = pick_hash_rand(step_cid, word.to_s)
              total += (rand * sides).floor + 1
            end

            total.to_s
          rescue ArgumentError, TypeError
            "NaN"
          end

          private

          def runtime_hash_from_context
            rt = @context&.registers&.[](:runtime)
            return TavernKit::Utils.deep_stringify_keys(rt.to_h) if rt.respond_to?(:to_h)

            raw = @context&.[]("runtime")
            raw.is_a?(Hash) ? raw : nil
          end

          def default_rng_word(word)
            w = word.to_s
            return w unless w.strip.empty?

            char = @context&.[]("char").to_s
            return char unless char.strip.empty?

            "0"
          end

          def normalize_pick_input(input)
            return input if input.is_a?(Array)

            s = input.to_s

            parsed = parse_json_array(s)
            return parsed if parsed

            s.gsub("\\,", "§X").split(/[:\,]/)
          end

          def parse_json_array(value)
            s = value.to_s
            return nil unless s.start_with?("[") && s.end_with?("]")

            arr = ::JSON.parse(s)
            arr.is_a?(Array) ? arr : nil
          rescue ::JSON::ParserError
            nil
          end

          # Deterministic pseudo-random float in [0, 1) derived from an integer id
          # and an input string.
          #
          # Derived from RisuAI's `pickHashRand(cid, word)`:
          # resources/Risuai/src/ts/util.ts (pickHashRand + sfc32).
          def pick_hash_rand(cid, word)
            hash_address = 5515

            rand_seed = lambda do |str|
              str.to_s.each_byte do |byte|
                hash_address = ((hash_address << 5) + hash_address) + byte
              end
              hash_address
            end

            rng = sfc32(rand_seed.call(word), rand_seed.call(word), rand_seed.call(word), rand_seed.call(word))

            (cid.to_i % 1000).times { rng.call }
            rng.call
          end

          def sfc32(a, b, c, d)
            a = to_i32(a)
            b = to_i32(b)
            c = to_i32(c)
            d = to_i32(d)

            lambda do
              t = to_i32(to_i32(a + b) + d)
              d = to_i32(d + 1)
              a = to_i32(b ^ ((b & 0xffff_ffff) >> 9))
              b = to_i32(c + to_i32(c << 3))
              c = to_i32(to_i32(c << 21) | ((c & 0xffff_ffff) >> 11))
              c = to_i32(c + t)
              (t & 0xffff_ffff) / 4_294_967_296.0
            end
          end

          def to_i32(value)
            v = value.to_i & 0xffff_ffff
            v >= 0x8000_0000 ? (v - 0x1_0000_0000) : v
          end
        end
      end
    end
  end
end
