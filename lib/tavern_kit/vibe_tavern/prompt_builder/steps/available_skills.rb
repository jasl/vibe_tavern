# frozen_string_literal: true

require_relative "../../tools/skills"

module TavernKit
  module VibeTavern
    module PromptBuilder
      module Steps
        # Step: inject available skill metadata for progressive disclosure.
        #
        # This step only exposes skill name/description (and optionally location)
        # in a machine-readable system block. Full SKILL.md bodies and bundled
        # files are fetched via tools.
        module AvailableSkills
          extend TavernKit::PromptBuilder::Step

          Config =
            Data.define do
              def self.from_hash(raw)
                return raw if raw.is_a?(self)

                raise ArgumentError, "available_skills step config must be a Hash" unless raw.is_a?(Hash)
                raw.each_key do |key|
                  raise ArgumentError, "available_skills step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
                end

                if raw.any?
                  raise ArgumentError, "available_skills step does not accept step config keys: #{raw.keys.inspect}"
                end

                new
              end
            end

          def self.before(ctx, _config)
            skills_cfg = TavernKit::VibeTavern::Tools::Skills::Config.from_context(ctx.context)
            return unless skills_cfg.enabled

            store = skills_cfg.store

            metas = store.list_skills
            return if metas.empty?

            xml =
              build_xml(
                metas,
                include_location: skills_cfg.include_location,
              )
            return if xml.strip.empty?

            insert_block!(ctx, xml, skills_count: metas.size)
          end

          class << self
            private

            def build_xml(metas, include_location:)
              include_location = include_location == true
              build_agentskills_xml_v1(metas, include_location: include_location)
            end

            def build_agentskills_xml_v1(metas, include_location:)
              lines = []
              lines << "<available_skills>"

              metas.each do |meta|
                lines << "  <skill>"
                lines << "    <name>#{xml_escape_text(meta.name)}</name>"
                lines << "    <description>#{xml_escape_text(meta.description)}</description>"

                if include_location
                  skill_md_path = File.expand_path(File.join(meta.location.to_s, "SKILL.md"))
                  lines << "    <location>#{xml_escape_text(skill_md_path)}</location>"
                end

                lines << "  </skill>"
              end

              lines << "</available_skills>"
              lines.join("\n")
            end

            def xml_escape_text(value)
              value
                .to_s
                .gsub("&", "&amp;")
                .gsub("<", "&lt;")
                .gsub(">", "&gt;")
            end

            def insert_block!(ctx, xml, skills_count:)
              ctx.blocks = Array(ctx.blocks).dup

              block =
                TavernKit::PromptBuilder::Block.new(
                  role: :system,
                  content: xml,
                  slot: :available_skills,
                  token_budget_group: :system,
                  metadata: { source: :available_skills, skills_count: skills_count.to_i },
                )

              insertion_index = resolve_insertion_index(ctx.blocks)
              ctx.blocks.insert(insertion_index, block)

              rebuild_plan!(ctx)
            end

            def resolve_insertion_index(blocks)
              user_index = blocks.find_index { |block| block.respond_to?(:slot) && block.slot == :user_message }
              return user_index if user_index

              tail_start_index = blocks.length
              while tail_start_index.positive?
                block = blocks[tail_start_index - 1]
                role = block.respond_to?(:role) ? block.role : nil
                break unless role == :user || role == :tool

                tail_start_index -= 1
              end

              return tail_start_index if tail_start_index < blocks.length

              blocks.length
            end

            def rebuild_plan!(ctx)
              plan = ctx.plan
              return unless plan

              ctx.plan = plan.with_blocks(ctx.blocks).with(warnings: ctx.warnings)
            end
          end
        end
      end
    end
  end
end
