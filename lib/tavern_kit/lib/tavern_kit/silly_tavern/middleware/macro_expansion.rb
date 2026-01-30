# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Middleware
      # Wave 4: expands {{macro}} syntax in block content via ST Macro engine.
      class MacroExpansion < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          ctx.expander ||= TavernKit::SillyTavern::Macro::V2Engine.new

          env = TavernKit::SillyTavern::ExpanderVars.build(ctx)

          expanded = Array(ctx.blocks).map do |block|
            content = block.content.to_s
            next block if content.empty?

            begin
              block.with(content: ctx.expander.expand(content, environment: env))
            rescue TavernKit::SillyTavern::MacroError => e
              ctx.warn("Macro expansion error: #{e.class}: #{e.message}")
              block
            end
          end

          ctx.blocks = expanded
          ctx.instrument(:stat, stage: :macro_expansion, key: :expanded_blocks, value: expanded.size) if ctx.instrumenter
        end
      end
    end
  end
end
