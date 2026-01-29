# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      # Macro execution flags parsed from prefixes inside `{{ ... }}`.
      #
      # ST defines 6 flags:
      # - ! immediate (parsed, not implemented)
      # - ? delayed (parsed, not implemented)
      # - ~ re-evaluate (parsed, not implemented)
      # - > filter (parsed, not implemented)
      # - / closing block (implemented by scoped macro pairing)
      # - # preserve whitespace (implemented for scoped content trimming)
      Flags = Data.define(
        :immediate,
        :delayed,
        :reevaluate,
        :filter,
        :closing_block,
        :preserve_whitespace,
        :raw,
      ) do
        def immediate? = immediate == true
        def delayed? = delayed == true
        def reevaluate? = reevaluate == true
        def filter? = filter == true
        def closing_block? = closing_block == true
        def preserve_whitespace? = preserve_whitespace == true

        def self.empty
          new(
            immediate: false,
            delayed: false,
            reevaluate: false,
            filter: false,
            closing_block: false,
            preserve_whitespace: false,
            raw: [],
          )
        end

        def self.parse(symbols)
          flags = empty
          Array(symbols).each do |sym|
            case sym.to_s
            when "!" then flags = flags.with(immediate: true)
            when "?" then flags = flags.with(delayed: true)
            when "~" then flags = flags.with(reevaluate: true)
            when ">" then flags = flags.with(filter: true)
            when "/" then flags = flags.with(closing_block: true)
            when "#" then flags = flags.with(preserve_whitespace: true)
            end
            flags = flags.with(raw: flags.raw + [sym.to_s])
          end

          flags
        end

        def with(**overrides)
          self.class.new(**deconstruct_keys(nil).merge(overrides))
        end
      end
    end
  end
end
