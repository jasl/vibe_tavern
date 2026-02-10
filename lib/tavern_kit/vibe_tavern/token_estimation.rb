# frozen_string_literal: true

require "pathname"

module TavernKit
  module VibeTavern
    # App-owned token estimation registry and model hint canonicalization.
    #
    # This keeps provider-specific model IDs out of TavernKit Core while still
    # allowing accurate token estimation via a small curated set of tokenizer
    # assets.
    module TokenEstimation
      module_function

      HF_TOKENIZER_FAMILIES = %i[hf_tokenizers huggingface_tokenizers tokenizers].freeze

      SOURCES = [
        {
          hint: "deepseek-v3",
          hf_repo: "deepseek-ai/DeepSeek-V3-0324",
        },
        {
          hint: "deepseek-v3.2",
          hf_repo: "deepseek-ai/DeepSeek-V3.2",
        },
        {
          hint: "qwen3",
          hf_repo: "Qwen/Qwen3-30B-A3B-Instruct-2507",
        },
        {
          hint: "qwen3-30b-a3b-instruct",
          hf_repo: "Qwen/Qwen3-30B-A3B-Instruct-2507",
        },
        {
          hint: "qwen3-next-80b-a3b-instruct",
          hf_repo: "Qwen/Qwen3-Next-80B-A3B-Instruct",
        },
        {
          hint: "qwen3-235b-a22b-instruct-2507",
          hf_repo: "Qwen/Qwen3-235B-A22B-Instruct-2507",
        },
        {
          hint: "glm-4.7",
          hf_repo: "zai-org/GLM-4.7",
        },
        {
          hint: "glm-4.7-flash",
          hf_repo: "zai-org/GLM-4.7-Flash",
        },
        {
          hint: "kimi-k2.5",
          tokenizer_family: :tiktoken,
        },
        {
          hint: "minimax-m2.1",
          hf_repo: "MiniMaxAI/MiniMax-M2.1",
        },
      ].freeze

      def canonical_model_hint(model_id)
        base = model_id.to_s.strip
        base = base.split(":", 2).first.to_s
        token = base.downcase

        if token.start_with?("openai/")
          # Prefer the OpenAI model name (helps tiktoken encoding selection).
          return base.split("/", 2).last.to_s
        end

        return "deepseek-v3.2" if token.include?("deepseek-v3.2")
        return "deepseek-v3" if token.include?("deepseek-chat-v3-0324") || token.include?("deepseek-v3-0324")
        return "deepseek-v3.2" if token.include?("deepseek")

        return "qwen3-next-80b-a3b-instruct" if token.include?("qwen3-next-80b-a3b-instruct")
        return "qwen3-235b-a22b-instruct-2507" if token.include?("qwen3-235b-a22b")
        return "qwen3-30b-a3b-instruct" if token.include?("qwen3-30b-a3b-instruct")
        return "qwen3" if token.include?("qwen3")

        return "glm-4.7-flash" if token.include?("glm-4.7-flash")
        return "glm-4.7" if token.include?("glm-4.7")
        return "kimi-k2.5" if token.include?("kimi-k2.5")
        return "minimax-m2.1" if token.include?("minimax-m2")

        base
      end

      def registry(root: default_root, tokenizer_root_path: nil)
        root = Pathname.new(root.to_s)
        root_dir = tokenizer_root_path || tokenizer_root(root: root)

        sources.each_with_object({}) do |source, registry|
          hint = source.fetch(:hint)
          family = source_tokenizer_family(source)
          repo = source[:hf_repo].to_s.strip

          entry = {
            tokenizer_family: family,
            source_hint: hint,
          }
          entry[:source_repo] = repo unless repo.empty?

          if hf_tokenizer_family?(family)
            entry[:tokenizer_path] = Pathname.new(root_dir).join(tokenizer_relative_path(hint)).to_s
          end

          registry[source.fetch(:hint)] = entry
        end
      end

      def estimator(root: default_root)
        root = Pathname.new(root.to_s).cleanpath
        root_dir = tokenizer_root(root: root)
        @estimators ||= {}
        cache_key = "#{root}|#{root_dir}"
        @estimators[cache_key] ||= TavernKit::TokenEstimator.new(registry: registry(root: root, tokenizer_root_path: root_dir))
      end

      def sources
        SOURCES.map(&:dup)
      end

      def tokenizer_relative_path(hint)
        File.join(hint.to_s, "tokenizer.json")
      end

      def tokenizer_path(root: default_root, hint:, tokenizer_root_path: nil)
        root_dir = tokenizer_root_path || tokenizer_root(root: root)
        Pathname.new(root_dir).join(tokenizer_relative_path(hint)).to_s
      end

      def tokenizer_root(root: default_root)
        root = Pathname.new(root.to_s)
        configured = credentials_tokenizer_root
        return root.join("vendor", "tokenizers").to_s if blank_path?(configured)

        configured_root = Pathname.new(configured.to_s)
        configured_root = root.join(configured_root) if configured_root.relative?
        configured_root.cleanpath.to_s
      end

      def default_root
        if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          Rails.root
        else
          Pathname.new(__dir__).join("../../..").cleanpath
        end
      end

      def credentials_tokenizer_root
        return nil unless defined?(Rails) && Rails.respond_to?(:app) && Rails.app

        Rails.app.creds.option(:token_estimation, :tokenizer_root)
      rescue StandardError
        nil
      end

      def blank_path?(value)
        value.nil? || value.to_s.strip.empty?
      end

      def source_tokenizer_family(source)
        source.fetch(:tokenizer_family, :hf_tokenizers).to_s.strip.downcase.tr("-", "_").to_sym
      end

      def hf_tokenizer_family?(family)
        HF_TOKENIZER_FAMILIES.include?(family)
      end
    end
  end
end
