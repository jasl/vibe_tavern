# frozen_string_literal: true

module OpenRouterSamplingProfiles
  class Entry < Struct.new(:id, :llm_options_defaults, :tags, :applies_to, keyword_init: true)
    def initialize(id:, llm_options_defaults: nil, tags: nil, applies_to: nil)
      super(
        id: id.to_s,
        llm_options_defaults: normalize_llm_options_defaults(llm_options_defaults),
        tags: normalize_tags(tags),
        applies_to: normalize_applies_to(applies_to),
      )
    end

    def matches?(raw_token)
      token = raw_token.to_s.strip.downcase
      return false if token.empty?

      candidates = ([id] + tags).map { |value| value.to_s.downcase }.uniq

      if token.include?("*")
        candidates.any? { |value| File.fnmatch(token, value) }
      else
        candidates.include?(token)
      end
    end

    def applies_to_model?(model_id)
      patterns = Array(applies_to).map { |p| p.to_s.strip }.reject(&:empty?)
      return true if patterns.empty?

      model = model_id.to_s
      patterns.any? { |pattern| File.fnmatch(pattern, model) }
    end

    private

    def normalize_llm_options_defaults(value)
      (value.is_a?(Hash) ? deep_symbolize_keys(value) : {}).tap do |out|
        out.delete(:model)
        out.delete(:messages)
        out.delete(:tools)
        out.delete(:tool_choice)
        out.delete(:response_format)
      end
    end

    def normalize_tags(value)
      Array(value).map { |v| v.to_s.strip.downcase }.reject(&:empty?).uniq
    end

    def normalize_applies_to(value)
      Array(value).map { |v| v.to_s.strip }.reject(&:empty?).uniq
    end

    def deep_symbolize_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(k, v), out|
          key = k.is_a?(Symbol) ? k : k.to_s.to_sym
          out[key] = deep_symbolize_keys(v) unless out.key?(key)
        end
      when Array
        value.map { |v| deep_symbolize_keys(v) }
      else
        value
      end
    end
  end

  class Catalog
    def self.build(&block)
      catalog = new
      catalog.instance_eval(&block) if block
      catalog.freeze
    end

    def initialize
      @entries = []
    end

    def profile(id, llm_options_defaults: nil, tags: nil, applies_to: nil)
      entry =
        Entry.new(
          id: id,
          llm_options_defaults: llm_options_defaults,
          tags: tags,
          applies_to: applies_to,
        )
      @entries << entry
      entry
    end

    def ids
      @entries.map(&:id)
    end

    def find(id)
      needle = id.to_s
      @entries.find { |e| e.id == needle }
    end

    def filter(raw_filter)
      tokens = raw_filter.to_s.split(",").map(&:strip).reject(&:empty?)
      return @entries.dup if tokens.empty? || tokens.any? { |token| %w[all full *].include?(token.downcase) }

      include_tokens = tokens.reject { |token| token.start_with?("!") }
      exclude_tokens = tokens.select { |token| token.start_with?("!") }.map { |t| t.delete_prefix("!") }.reject(&:empty?)

      selected =
        if include_tokens.empty?
          @entries
        else
          @entries.select { |entry| include_tokens.any? { |token| entry.matches?(token) } }
        end

      selected.reject { |entry| exclude_tokens.any? { |token| entry.matches?(token) } }
    end
  end

  DEFAULT_PROFILE_ID = "default"

  CATALOG =
    Catalog.build do
      profile DEFAULT_PROFILE_ID, tags: %w[default baseline], llm_options_defaults: {}

      profile(
        "deepseek_v3_2_local_recommended",
        tags: %w[deepseek v3_2 recommended],
        applies_to: ["deepseek/deepseek-v3.2*"],
        llm_options_defaults: { temperature: 1.0, top_p: 0.95 },
      )

      profile(
        "deepseek_v3_2_general_conversation",
        tags: %w[deepseek v3_2 conversation],
        applies_to: ["deepseek/deepseek-v3.2*"],
        llm_options_defaults: { temperature: 1.3, top_p: 0.95 },
      )

      profile(
        "deepseek_v3_2_creative_writing",
        tags: %w[deepseek v3_2 creative],
        applies_to: ["deepseek/deepseek-v3.2*"],
        llm_options_defaults: { temperature: 1.5, top_p: 0.95 },
      )

      profile(
        "deepseek_chat_t0_8",
        tags: %w[deepseek chat],
        applies_to: ["deepseek/deepseek-chat-v3-*"],
        llm_options_defaults: { temperature: 0.8 },
      )

      profile(
        "deepseek_chat_t1_0",
        tags: %w[deepseek chat],
        applies_to: ["deepseek/deepseek-chat-v3-*"],
        llm_options_defaults: { temperature: 1.0 },
      )

      profile(
        "grok_default",
        tags: %w[x_ai grok recommended],
        applies_to: ["x-ai/grok-*"],
        llm_options_defaults: { temperature: 0.3 },
      )

      profile(
        "gemini_2_5_flash_default",
        tags: %w[google gemini],
        applies_to: ["google/gemini-2.5-flash*"],
        llm_options_defaults: { temperature: 1.0 },
      )

      profile(
        "gemini_2_5_flash_creative",
        tags: %w[google gemini creative],
        applies_to: ["google/gemini-2.5-flash*"],
        llm_options_defaults: { temperature: 1.5 },
      )

      profile(
        "minimax_m2_1_recommended",
        tags: %w[minimax recommended],
        applies_to: ["minimax/minimax-m2.1*"],
        llm_options_defaults: { temperature: 1.0, top_p: 0.95, top_k: 40 },
      )

      profile(
        "qwen_recommended",
        tags: %w[qwen recommended],
        applies_to: ["qwen/qwen3-*"],
        llm_options_defaults: { temperature: 0.7, top_p: 0.8, top_k: 20, min_p: 0 },
      )

      profile(
        "glm_4_7_recommended",
        tags: %w[z_ai glm recommended],
        applies_to: ["z-ai/glm-4.7:nitro"],
        llm_options_defaults: { temperature: 1.0, top_p: 0.95 },
      )

      profile(
        "glm_4_7_t0_85",
        tags: %w[z_ai glm],
        applies_to: ["z-ai/glm-4.7:nitro"],
        llm_options_defaults: { temperature: 0.85, top_p: 0.95 },
      )

      profile(
        "glm_4_7_flash_general",
        tags: %w[z_ai glm flash],
        applies_to: ["z-ai/glm-4.7-flash*"],
        llm_options_defaults: { temperature: 1.0, top_p: 0.95 },
      )

      profile(
        "glm_4_7_flash_tool_calling",
        tags: %w[z_ai glm flash tool_calling],
        applies_to: ["z-ai/glm-4.7-flash*"],
        llm_options_defaults: { temperature: 0.7, top_p: 1.0 },
      )

      profile(
        "kimi_k2_5_instant",
        tags: %w[moonshot kimi recommended],
        applies_to: ["moonshotai/kimi-k2.5*"],
        llm_options_defaults: { temperature: 0.6, top_p: 0.95 },
      )
    end
end
