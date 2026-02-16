# frozen_string_literal: true

module AgentCore
  module Resources
    module PromptInjections
      module Factory
        module_function

        def build_sources(specs:, text_store: nil)
          Array(specs).filter_map do |spec|
            build_source(spec, text_store: text_store)
          end
        rescue StandardError
          []
        end

        def build_source(spec, text_store:)
          return nil unless spec.is_a?(Hash)

          h = AgentCore::Utils.deep_symbolize_keys(spec)
          enabled = h.fetch(:enabled, true)
          return nil unless enabled

          type = h.fetch(:type, nil).to_s.strip
          return nil if type.empty?

          case type
          when "provided"
            Sources::Provided.new(
              context_key: h.fetch(:context_key, Sources::Provided::DEFAULT_CONTEXT_KEY),
            )
          when "text_store", "text_store_entries"
            Sources::TextStoreEntries.new(
              text_store: text_store,
              entries: h.fetch(:entries, []),
            )
          when "file_set"
            Sources::FileSet.new(
              files: h.fetch(:files, []),
              order: h.fetch(:order, 0),
              prompt_modes: h.fetch(:prompt_modes, PROMPT_MODES),
              root_key: h[:root_key],
              total_max_bytes: h[:total_max_bytes],
              marker: h.fetch(:marker, Truncation::DEFAULT_MARKER),
              section_header: h.fetch(:section_header, Sources::FileSet::DEFAULT_SECTION_HEADER),
              substitute_variables: h[:substitute_variables] == true,
              include_missing: h.fetch(:include_missing, true),
            )
          when "repo_docs"
            Sources::RepoDocs.new(
              filenames: h.fetch(:filenames, Sources::RepoDocs::DEFAULT_FILENAMES),
              max_total_bytes: h[:max_total_bytes],
              order: h.fetch(:order, 0),
              prompt_modes: h.fetch(:prompt_modes, PROMPT_MODES),
              wrapper_template: h.fetch(:wrapper_template, Sources::RepoDocs::DEFAULT_WRAPPER_TEMPLATE),
              marker: h.fetch(:marker, Truncation::DEFAULT_MARKER),
            )
          else
            nil
          end
        rescue StandardError
          nil
        end
      end
    end
  end
end
