# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      module Macros
        module_function

        # Upstream reference:
        # resources/Risuai/src/ts/cbs.ts (br/cbr + displayescaped* helpers)

        def resolve_br(_args)
          "\n"
        end
        private_class_method :resolve_br

        def resolve_cbr(args)
          # Intended semantics (per docs): return the literal "\n", repeated when an argument is provided.
          # Note: upstream implementation appears to repeat the raw token string; we prefer the documented
          # behavior because it is stable and useful for prompt building.
          return "\\n" if args.empty?

          n = args[0].to_s.to_f
          n = 1 if n < 1
          "\\n" * n.to_i
        end
        private_class_method :resolve_cbr

        def resolve_displayescapedbracketopen(_args)
          "\u{E9BA}"
        end
        private_class_method :resolve_displayescapedbracketopen

        def resolve_displayescapedbracketclose(_args)
          "\u{E9BB}"
        end
        private_class_method :resolve_displayescapedbracketclose

        def resolve_displayescapedanglebracketopen(_args)
          "\u{E9BC}"
        end
        private_class_method :resolve_displayescapedanglebracketopen

        def resolve_displayescapedanglebracketclose(_args)
          "\u{E9BD}"
        end
        private_class_method :resolve_displayescapedanglebracketclose

        def resolve_displayescapedcolon(_args)
          "\u{E9BE}"
        end
        private_class_method :resolve_displayescapedcolon

        def resolve_displayescapedsemicolon(_args)
          "\u{E9BF}"
        end
        private_class_method :resolve_displayescapedsemicolon
      end
    end
  end
end
