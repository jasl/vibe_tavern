# frozen_string_literal: true

require_relative "skill_metadata"

module TavernKit
  module VibeTavern
    module Tools
      module Skills
        Skill =
          Data.define(
            :meta,
            :body_markdown,
            :files_index,
          ) do
            def initialize(meta:, body_markdown:, files_index: nil)
              raise ArgumentError, "meta must be a Tools::Skills::SkillMetadata" unless meta.is_a?(SkillMetadata)

              normalized_index = normalize_files_index(files_index)

              super(
                meta: meta,
                body_markdown: body_markdown.to_s,
                files_index: normalized_index,
              )
            end

            private

            def normalize_files_index(value)
              hash = value.is_a?(Hash) ? value : {}

              scripts = normalize_rel_paths(hash.fetch(:scripts, []))
              references = normalize_rel_paths(hash.fetch(:references, []))
              assets = normalize_rel_paths(hash.fetch(:assets, []))

              {
                scripts: scripts,
                references: references,
                assets: assets,
              }
            end

            def normalize_rel_paths(value)
              Array(value)
                .map { |v| v.to_s.strip }
                .reject(&:empty?)
                .sort
            end
          end
      end
    end
  end
end
