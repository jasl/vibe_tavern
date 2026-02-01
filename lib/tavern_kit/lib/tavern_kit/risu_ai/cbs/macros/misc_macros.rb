# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      module Macros
        module_function

        def resolve_calc(args, environment:)
          expr = args[0].to_s
          TavernKit::RisuAI::CBS::Engine.new.expand("{{? #{expr}}}", environment: environment)
        rescue StandardError
          "0"
        end
        private_class_method :resolve_calc

        def resolve_hiddenkey(_args)
          ""
        end
        private_class_method :resolve_hiddenkey

        def resolve_reverse(name, args)
          ([name.to_s] + Array(args).map(&:to_s)).join("::").reverse
        end
        private_class_method :resolve_reverse

        def resolve_comment(args, environment:)
          # In the RisuAI UI, {{comment}} is rendered into HTML for display only.
          # During prompt building (non-display mode), it should not affect output.
          displaying = environment.respond_to?(:displaying) ? environment.displaying : nil
          displaying == true ? %(<div class="risu-comment">#{args[0]}</div>) : ""
        rescue StandardError
          ""
        end
        private_class_method :resolve_comment

        def resolve_tex(args)
          "$$#{args[0]}$$"
        end
        private_class_method :resolve_tex

        def resolve_ruby(args)
          base = args[0].to_s
          reading = args[1].to_s
          "<ruby>#{base}<rp> (</rp><rt>#{reading}</rt><rp>) </rp></ruby>"
        end
        private_class_method :resolve_ruby

        def resolve_codeblock(args)
          return "" if args.empty?

          code = html_escape_code(args[-1].to_s)

          if args.length > 1
            lang = args[0].to_s
            %(<pre-hljs-placeholder lang="#{lang}">#{code}</pre-hljs-placeholder>)
          else
            %(<pre><code>#{code}</code></pre>)
          end
        rescue StandardError
          ""
        end
        private_class_method :resolve_codeblock

        def html_escape_code(code)
          code
            .gsub("\"", "&quot;")
            .gsub("'", "&#39;")
            .gsub("<", "&lt;")
            .gsub(">", "&gt;")
        end
        private_class_method :html_escape_code
      end
    end
  end
end
