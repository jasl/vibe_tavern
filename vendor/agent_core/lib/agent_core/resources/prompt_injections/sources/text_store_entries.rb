# frozen_string_literal: true

module AgentCore
  module Resources
    module PromptInjections
      module Sources
        class TextStoreEntries < Source::Base
          def initialize(text_store:, entries:)
            @text_store = text_store
            @entries = Array(entries)
          end

          def items(agent:, user_message:, execution_context:, prompt_mode:)
            return [] unless @text_store

            @entries.filter_map do |entry|
              build_item(entry)
            end
          rescue StandardError
            []
          end

          private

          def build_item(entry)
            h = entry.is_a?(Hash) ? AgentCore::Utils.symbolize_keys(entry) : {}

            key = h.fetch(:key).to_s
            target = h.fetch(:target).to_sym

            text = @text_store.fetch(key: key)
            return nil if text.nil?

            content = apply_wrapper(text, h[:wrapper])
            if (max_bytes = h[:max_bytes])
              content = Truncation.head_marker_tail(content, max_bytes: max_bytes)
            end

            Item.new(
              target: target,
              content: content,
              order: h.fetch(:order, 0),
              prompt_modes: h.fetch(:prompt_modes, PROMPT_MODES),
              role: h[:role],
              substitute_variables: h[:substitute_variables] == true,
              id: h[:id],
              metadata: h[:metadata],
            )
          rescue StandardError
            nil
          end

          def apply_wrapper(content, wrapper)
            return content.to_s if wrapper.nil?

            if wrapper.is_a?(String)
              return wrapper.include?("{{content}}") ? wrapper.gsub("{{content}}", content.to_s) : "#{wrapper}\n#{content}"
            end

            return content.to_s unless wrapper.is_a?(Hash)

            w = AgentCore::Utils.symbolize_keys(wrapper)
            if w[:template]
              w[:template].to_s.gsub("{{content}}", content.to_s)
            else
              "#{w[:prefix]}#{content}#{w[:suffix]}"
            end
          rescue StandardError
            content.to_s
          end
        end
      end
    end
  end
end
