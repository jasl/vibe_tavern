# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      # Minimal CBS engine.
      #
      # This starts with the escape/pure family and basic #if/#when semantics.
      # Additional CBS features are implemented here as upstream parity requires.
      class Engine < TavernKit::Macro::Engine::Base
        OPEN = "{{"
        CLOSE = "}}"
        BLOCK_END_TOKEN = "/"

        def expand(text, environment:)
          # Per-parse state (mirrors upstream): functions persist across nested
          # call:: expansions, but reset for each top-level render.
          @functions = {}
          @call_stack = 0

          expand_with_call_stack(text.to_s, environment: environment)
        end

        private

        ForceReturn = Class.new(StandardError) do
          attr_reader :value

          def initialize(value)
            super()
            @value = value
          end
        end

        Block = Struct.new(:type, :mode, :keep, :expr, :args, keyword_init: true)

        def expand_stream(str, index, environment:, stop_on_end:)
          out = +""
          i = index

          while (open_idx = str.index(OPEN, i))
            out << str[i...open_idx]

            close_idx = find_close_idx(str, open_idx)
            unless close_idx
              out << str[open_idx..]
              return [out, str.length, false]
            end

            raw = str[(open_idx + OPEN.length)...close_idx]
            token = raw.to_s.strip

            if close_token?(token) && stop_on_end
              return [out, close_idx + CLOSE.length, true]
            end

            if token.start_with?("#")
              replacement, next_i = expand_block(str, open_idx: open_idx, close_idx: close_idx, token: token, environment: environment)
              if replacement
                out << replacement
                i = next_i
              else
                # Preserve original tag when the block can't be parsed yet.
                out << str[open_idx..(close_idx + CLOSE.length - 1)]
                i = close_idx + CLOSE.length
              end
              next
            end

            if close_token?(token)
              # Stray close tag at top-level is preserved.
              out << str[open_idx..(close_idx + CLOSE.length - 1)]
              i = close_idx + CLOSE.length
              next
            end

            out << expand_tag(raw, token: token, environment: environment, out_buffer: out)
            i = close_idx + CLOSE.length
          end

          out << str[i..] if i < str.length
          [out, str.length, false]
        end
        # Implementation methods are split into:
        # - `risu_ai/cbs/engine/blocks.rb`
        # - `risu_ai/cbs/engine/tags.rb`
        # - `risu_ai/cbs/engine/parser.rb`
        # - `risu_ai/cbs/engine/rpn_calc.rb`

        def expand_with_call_stack(str, environment:)
          @call_stack += 1
          return "ERROR: Call stack limit reached" if @call_stack > 20

          env = environment.respond_to?(:call_frame) ? environment.call_frame : environment

          out, = expand_stream(str, 0, environment: env, stop_on_end: false)
          out
        rescue ForceReturn => e
          e.value
        ensure
          @call_stack -= 1
        end
      end
    end
  end
end

require_relative "engine/blocks"
require_relative "engine/tags"
require_relative "engine/rpn_calc"
require_relative "engine/parser"
