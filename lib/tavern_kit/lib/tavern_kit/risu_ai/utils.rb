# frozen_string_literal: true

module TavernKit
  module RisuAI
    # Utilities that mirror small deterministic helpers from upstream RisuAI.
    #
    # Keep this namespace RisuAI-only; do not reuse from SillyTavern/Core.
    module Utils
      module_function

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
      private_class_method :sfc32, :to_i32
    end
  end
end
