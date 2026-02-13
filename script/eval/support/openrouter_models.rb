# frozen_string_literal: true

# Centralized OpenRouter eval model catalog.
#
# Keep model IDs/tags/workarounds here so all eval scripts stay in sync.
module VibeTavernEval
  module OpenRouterModels
    Entry =
      Struct.new(
        :id,
        :tags,
        :workarounds,
        keyword_init: true,
      ) do
        def initialize(id:, tags: [], workarounds: nil)
          super(
            id: id.to_s,
            tags: normalize_tags(tags),
            workarounds: normalize_workarounds(workarounds),
          )
        end

        def workarounds_for(suite)
          Array(workarounds.fetch(suite.to_sym, []))
        end

        private

        def normalize_tags(value)
          Array(value).map { |t| t.to_s.strip.downcase }.reject(&:empty?).uniq
        end

        def normalize_workarounds(value)
          h = value.is_a?(Hash) ? value : {}

          h.each_with_object({}) do |(k, v), out|
            key = k.to_s.strip.downcase.tr("-", "_").to_sym
            out[key] = Array(v).map { |w| w.to_s.strip.downcase.tr("-", "_").to_sym }.uniq
          end
        end
      end

    CATALOG = [
      Entry.new(
        id: "deepseek/deepseek-v3.2:nitro",
        tags: %w[deepseek ds],
        workarounds: { tool_call: [:deepseek_openrouter_compat] },
      ),
      Entry.new(
        id: "deepseek/deepseek-chat-v3-0324:nitro",
        tags: %w[deepseek ds chat],
        workarounds: { tool_call: [:deepseek_openrouter_compat] },
      ),
      Entry.new(
        id: "x-ai/grok-4.1-fast",
        tags: %w[x_ai grok],
      ),
      Entry.new(
        id: "google/gemini-2.5-flash:nitro",
        tags: %w[google gemini stable],
        workarounds: { tool_call: [:gemini_openrouter_compat] },
      ),
      Entry.new(
        id: "google/gemini-3-flash-preview:nitro",
        tags: %w[google gemini],
        workarounds: { tool_call: [:gemini_openrouter_compat] },
      ),
      Entry.new(
        id: "google/gemini-3-pro-preview:nitro",
        tags: %w[google gemini],
        workarounds: { tool_call: [:gemini_openrouter_compat] },
      ),
      Entry.new(
        id: "anthropic/claude-opus-4.6:nitro",
        tags: %w[anthropic claude stable],
        workarounds: { directives: [:json_object_first] },
      ),
      Entry.new(
        id: "openai/gpt-5.2-chat:nitro",
        tags: %w[openai gpt],
        workarounds: { directives: [:prompt_only] },
      ),
      Entry.new(
        id: "openai/gpt-5.2:nitro",
        tags: %w[openai gpt stable],
        workarounds: { directives: [:prompt_only] },
      ),
      Entry.new(
        id: "minimax/minimax-m2-her",
        tags: %w[minimax],
        workarounds: { tool_call: [:tool_use_disabled], directives: [:prompt_only] },
      ),
      Entry.new(
        id: "minimax/minimax-m2.5:nitro",
        tags: %w[minimax],
        workarounds: { tool_call: [:content_tag_tool_call_fallback], directives: [:prompt_only] },
      ),
      Entry.new(
        id: "qwen/qwen3-30b-a3b-instruct-2507:nitro",
        tags: %w[qwen stable],
      ),
      Entry.new(
        id: "qwen/qwen3-next-80b-a3b-instruct:nitro",
        tags: %w[qwen stable],
      ),
      Entry.new(
        id: "qwen/qwen3-235b-a22b-2507:nitro",
        tags: %w[qwen stable],
        workarounds: { tool_call: [:content_tag_tool_call_fallback] },
      ),
      Entry.new(
        id: "z-ai/glm-5:nitro",
        tags: %w[z_ai glm],
        workarounds: { tool_call: [:content_tag_tool_call_fallback] },
      ),
      Entry.new(
        id: "z-ai/glm-4.7-flash:nitro",
        tags: %w[z_ai glm],
        workarounds: { tool_call: [:content_tag_tool_call_fallback] },
      ),
      Entry.new(
        id: "moonshotai/kimi-k2.5:nitro",
        tags: %w[moonshot kimi],
      ),
    ].freeze

    module_function

    def entries
      CATALOG.dup
    end

    def ids
      CATALOG.map(&:id)
    end
  end
end
