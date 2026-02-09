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

      DEFAULT_REVISION = "main"

      def canonical_model_hint(model_id)
        base = model_id.to_s.strip
        base = base.split(":", 2).first.to_s
        token = base.downcase

        return "deepseek" if token.include?("deepseek")
        return "qwen3" if token.include?("qwen3")

        if token.start_with?("openai/")
          # Prefer the OpenAI model name (helps tiktoken encoding selection).
          return base.split("/", 2).last.to_s
        end

        base
      end

      def registry(root: default_root)
        root = Pathname.new(root.to_s)

        {
          "deepseek" => {
            tokenizer_family: :hf_tokenizers,
            tokenizer_path: root.join("vendor/tokenizers/deepseek/tokenizer.json").to_s,
          },
          "qwen3" => {
            tokenizer_family: :hf_tokenizers,
            tokenizer_path: root.join("vendor/tokenizers/qwen3/tokenizer.json").to_s,
          },
        }
      end

      def estimator(root: default_root)
        root = Pathname.new(root.to_s).cleanpath
        @estimators ||= {}
        @estimators[root.to_s] ||= TavernKit::TokenEstimator.new(registry: registry(root: root))
      end

      def sources
        [
          {
            hint: "deepseek",
            hf_repo: "deepseek-ai/DeepSeek-V3-0324",
            revision: DEFAULT_REVISION,
            relative_path: "vendor/tokenizers/deepseek/tokenizer.json",
          },
          {
            hint: "qwen3",
            hf_repo: "Qwen/Qwen3-30B-A3B-Instruct-2507",
            revision: DEFAULT_REVISION,
            relative_path: "vendor/tokenizers/qwen3/tokenizer.json",
          },
        ]
      end

      def default_root
        if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          Rails.root
        else
          Pathname.new(__dir__).join("../../..").cleanpath
        end
      end
    end
  end
end
