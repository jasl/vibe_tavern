# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module LanguagePolicy
      SUPPORTED_TARGET_LANGS = %w[
        en-US
        zh-CN
        zh-TW
        ko-KR
        ja-JP
        yue-HK
      ].freeze

      CANONICAL_TARGET_LANGS = {
        "en" => "en-US",
        "en-us" => "en-US",
        "zh-cn" => "zh-CN",
        "zh-tw" => "zh-TW",
        "zh-hans" => "zh-CN",
        "zh-hans-cn" => "zh-CN",
        "zh-hant" => "zh-TW",
        "zh-hant-tw" => "zh-TW",
        "ko-kr" => "ko-KR",
        "ko" => "ko-KR",
        "ja-jp" => "ja-JP",
        "ja" => "ja-JP",
        "yue-hk" => "yue-HK",
        "yue" => "yue-HK",
      }.freeze

      Config =
        Data.define(
          :enabled,
          :target_lang,
          :style_hint,
          :special_tags,
          :policy_text_builder,
        ) do
          def self.from_runtime(runtime)
            raw = runtime&.[](:language_policy)
            return new(enabled: false, target_lang: nil, style_hint: nil, special_tags: [], policy_text_builder: nil) if raw.nil?

            raise ArgumentError, "runtime[:language_policy] must be a Hash" unless raw.is_a?(Hash)
            raw.each_key do |k|
              raise ArgumentError, "language_policy config keys must be Symbols (got #{k.class})" unless k.is_a?(Symbol)
            end

            enabled = raw.fetch(:enabled, false) ? true : false

            raw_target = raw.fetch(:target_lang, nil)
            target_lang = TavernKit::VibeTavern::LanguagePolicy.canonical_target_lang(raw_target)

            style_hint = raw.fetch(:style_hint, nil)&.to_s&.strip
            style_hint = nil if style_hint.to_s.empty?

            special_tags =
              Array(raw.fetch(:special_tags, []))
                .map { |item| item.to_s.strip }
                .reject(&:empty?)
                .uniq

            policy_text_builder = raw.fetch(:policy_text_builder, nil)
            if policy_text_builder && !policy_text_builder.respond_to?(:call)
              raise ArgumentError, "language_policy.policy_text_builder must respond to #call"
            end

            new(
              enabled: enabled,
              target_lang: target_lang,
              style_hint: style_hint,
              special_tags: special_tags,
              policy_text_builder: policy_text_builder,
            )
          end
        end

      module_function

      def canonical_target_lang(raw)
        s = raw.to_s.strip.tr("_", "-")
        return nil if s.empty?

        normalized = TavernKit::Text::LanguageTag.normalize(s) || s
        CANONICAL_TARGET_LANGS.fetch(normalized.downcase, normalized)
      end
    end
  end
end
