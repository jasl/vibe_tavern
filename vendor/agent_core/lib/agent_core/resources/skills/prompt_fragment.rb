# frozen_string_literal: true

module AgentCore
  module Resources
    module Skills
      # Prompt fragments for exposing skills metadata to the LLM.
      module PromptFragment
        module_function

        def available_skills_xml(store:, include_location: false)
          metas = store.list_skills

          out = +"<available_skills>\n"

          metas.each do |meta|
            attrs = {
              name: meta.name,
              description: meta.description,
            }
            attrs[:allowed_tools] = Array(meta.allowed_tools).join(" ") if meta.allowed_tools&.any?
            attrs[:location] = meta.location if include_location

            out << "  <skill"
            attrs.each do |k, v|
              out << " #{k}=\"#{escape_xml_attr(v)}\""
            end
            out << " />\n"
          end

          out << "</available_skills>"
          out
        end

        def escape_xml_attr(value)
          value.to_s
            .gsub("&", "&amp;")
            .gsub("<", "&lt;")
            .gsub(">", "&gt;")
            .gsub("\"", "&quot;")
        end
        private_class_method :escape_xml_attr
      end
    end
  end
end
