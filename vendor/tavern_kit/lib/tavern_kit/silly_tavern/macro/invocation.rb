# frozen_string_literal: true

require "zlib"

require_relative "flags"

module TavernKit
  module SillyTavern
    module Macro
      # A single macro call site within an expansion pass.
      #
      # This object is passed to macro handlers so they can access:
      # - parsed args (best-effort in V1)
      # - deterministic pick seeding (content_hash + input hash + offset)
      # - variable/outlet helpers
      Invocation = Data.define(
        :raw_inner,
        :key,
        :name,
        :args,
        :raw_args,
        :flags,
        :is_scoped,
        :range,
        :offset,
        :raw_content_hash,
        :environment,
        :resolver,
        :trimmer,
        :warner,
      ) do
        def global_offset = offset

        def raw
          "{{#{raw_inner}}}"
        rescue StandardError
          ""
        end

        def resolve(text, offset_delta: 0)
          return text.to_s unless resolver.respond_to?(:call)

          resolver.call(text.to_s, offset_delta: offset_delta.to_i)
        end

        def trim_content(content, trim_indent: true)
          return content.to_s unless trimmer.respond_to?(:call)

          trimmer.call(content.to_s, trim_indent: trim_indent == true)
        end

        def warn(message)
          msg = message.to_s

          if warner.respond_to?(:call)
            warner.call(msg)
          elsif environment.respond_to?(:warn)
            environment.warn(msg)
          end

          nil
        end

        def now
          environment.respond_to?(:now) ? environment.now : Time.now
        end

        def outlets
          environment.respond_to?(:outlets) ? environment.outlets : nil
        end

        def rng_or_new
          if environment.respond_to?(:rng) && environment.rng
            environment.rng
          else
            Random.new(Random.new_seed)
          end
        end

        # ST list splitting helper used by macros like {{random::...}} / {{pick::...}}.
        #
        # Supports:
        # - `a,b,c` with `\,` escape
        # - `a::b::c` for explicit `::` splitting
        def split_list(source = args)
          str = source.to_s
          return [] if str.strip.empty?

          if str.include?("::")
            str.split("::")
          else
            placeholder = "##COMMA##"
            str
              .gsub("\\,", placeholder)
              .split(",")
              .map { |item| item.strip.gsub(placeholder, ",") }
          end
        end

        # Deterministic pick helper inspired by ST's {{pick}} behavior.
        #
        # Uses:
        # - environment.content_hash (chat identity / stable seed; optional)
        # - raw_content_hash (hash of the original input string)
        # - offset (placement inside the input)
        def pick_index(length)
          length = length.to_i
          return 0 if length <= 0

          base_seed = if environment.respond_to?(:content_hash)
            environment.content_hash
          else
            nil
          end

          combined = "#{base_seed}-#{raw_content_hash}-#{offset}"
          seed = self.class.stable_hash(combined)

          Random.new(seed).rand(length)
        end

        def self.stable_hash(value)
          Zlib.crc32(value.to_s.b)
        rescue StandardError
          0
        end
      end
    end
  end
end
