# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Middleware
      # Wave 5f Stage 1/2 boundary: assemble prompt blocks from template + groups.
      class TemplateAssembly < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          template = ctx[:risuai_template]
          groups = ctx[:risuai_groups]

          template = [] unless template.is_a?(Array)
          groups = {} unless groups.is_a?(Hash)

          ctx.blocks = TavernKit::RisuAI::TemplateCards.assemble(
            template: template,
            groups: groups,
            lore_entries: Array(ctx.lore_result&.activated_entries),
          )
        end
      end
    end
  end
end
