# frozen_string_literal: true

module AgentCore
  module Resources
    module PromptInjections
      module Sources
        class Provided < Source::Base
          DEFAULT_CONTEXT_KEY = :prompt_injections

          def initialize(context_key: DEFAULT_CONTEXT_KEY)
            @context_key = context_key.to_sym
          end

          def items(agent:, user_message:, execution_context:, prompt_mode:)
            raw = execution_context.attributes[@context_key]
            return [] unless raw.is_a?(Array)

            raw.filter_map do |entry|
              case entry
              when Item
                entry
              when Hash
                build_item_from_hash(entry)
              else
                nil
              end
            end
          rescue StandardError
            []
          end

          private

          def build_item_from_hash(value)
            h = AgentCore::Utils.symbolize_keys(value)

            content = h.fetch(:content, "")
            if (max_bytes = h[:max_bytes])
              content = Truncation.head_marker_tail(content, max_bytes: max_bytes)
            end

            Item.new(
              target: h.fetch(:target),
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
        end
      end
    end
  end
end
