# frozen_string_literal: true

module TavernKit
  module RisuAI
    module PromptBuilder
      module Steps
      # Assemble prompt blocks from template + groups.
      module TemplateAssembly
        extend TavernKit::PromptBuilder::Step

        Config =
          Data.define do
            def self.from_hash(raw)
              return raw if raw.is_a?(self)

              raise ArgumentError, "template_assembly step config must be a Hash" unless raw.is_a?(Hash)
              raw.each_key do |key|
                raise ArgumentError, "template_assembly step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
              end

              if raw.any?
                raise ArgumentError, "template_assembly step does not accept step config keys: #{raw.keys.inspect}"
              end

              new
            end
          end

        def self.before(ctx, _config)
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
end
