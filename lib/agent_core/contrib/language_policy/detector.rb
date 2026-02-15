# frozen_string_literal: true

module AgentCore
  module Contrib
    module LanguagePolicy
      module Detector
        CANONICAL_TARGET_LANGS = {
          "en" => "en-US",
          "en-us" => "en-US",
          "zh-cn" => "zh-CN",
          "zh-tw" => "zh-TW",
          "zh-hans" => "zh-CN",
          "zh-hans-cn" => "zh-CN",
          "zh-hant" => "zh-TW",
          "zh-hant-tw" => "zh-TW",
          "ja" => "ja-JP",
          "ja-jp" => "ja-JP",
          "ko" => "ko-KR",
          "ko-kr" => "ko-KR",
          "yue" => "yue-HK",
          "yue-hk" => "yue-HK",
        }.freeze

        DETECTABLE_TARGET_LANGS = %w[
          ja-JP
          ko-KR
          yue-HK
          zh-CN
          zh-TW
        ].freeze

        module_function

        def canonical_target_lang(raw)
          s = raw.to_s.strip.tr("_", "-")
          return "" if s.empty?

          CANONICAL_TARGET_LANGS.fetch(s.downcase, s)
        end

        def language_shape(text, target_lang:)
          lang = canonical_target_lang(target_lang)
          return :unknown if lang.empty?
          return :unknown unless DETECTABLE_TARGET_LANGS.include?(lang)

          t = strip_verbatim_zones(strip_language_spans(text))
          return :unknown if t.strip.empty?

          has_kana = t.match?(/[\u3040-\u30FF]/)
          has_han = t.match?(/\p{Han}/)
          has_hangul = t.match?(/[\uAC00-\uD7AF]/)
          has_latin = t.match?(/[A-Za-z]/)

          case lang
          when "ja-JP"
            return :ok if has_kana
            return :unknown if has_han
            return :drift if has_hangul
            return :unknown if has_latin

            :unknown
          when "zh-CN", "zh-TW", "yue-HK"
            return :drift if has_kana
            return :ok if has_han
            return :drift if has_hangul
            return :unknown if has_latin

            :unknown
          when "ko-KR"
            return :ok if has_hangul
            return :unknown if has_han
            return :drift if has_kana
            return :unknown if has_latin

            :unknown
          else
            :unknown
          end
        rescue StandardError
          :unknown
        end

        def strip_language_spans(text)
          text.to_s.gsub(/<\s*lang\b[^>]*>.*?<\/\s*lang\s*>/im, "")
        rescue StandardError
          text.to_s
        end

        def strip_verbatim_zones(text)
          s = text.to_s.dup
          s.gsub!(/```.*?```/m, " ")
          s.gsub!(/`[^`]*`/, " ")
          s.gsub!(/{{.*?}}/m, " ")
          s.gsub!(/{%.*?%}/m, " ")
          s.gsub!(/\[[^\]]+\]\((https?:\/\/[^\)]+)\)/i, " ")
          s.gsub!(/https?:\/\/\S+/i, " ")
          s.gsub!(/<[^>]+>/, " ")
          s
        rescue StandardError
          text.to_s
        end
      end
    end
  end
end
