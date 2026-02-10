# frozen_string_literal: true

require "test_helper"

class TavernKit::Text::LanguageTagTest < Minitest::Test
  def test_normalize_canonicalizes_common_forms
    assert_equal "ja-JP", TavernKit::Text::LanguageTag.normalize("ja-jp")
    assert_equal "zh-Hans-CN", TavernKit::Text::LanguageTag.normalize("zh_hans_cn")
    assert_equal "en", TavernKit::Text::LanguageTag.normalize("en")
    assert_equal "yue-HK", TavernKit::Text::LanguageTag.normalize("yue-hk")
  end

  def test_normalize_returns_nil_for_invalid_syntax
    assert_nil TavernKit::Text::LanguageTag.normalize("")
    assert_nil TavernKit::Text::LanguageTag.normalize("not a tag")
    assert_nil TavernKit::Text::LanguageTag.normalize("x-klingon")
  end

  def test_valid_predicate
    assert TavernKit::Text::LanguageTag.valid?("ja-JP")
    refute TavernKit::Text::LanguageTag.valid?("not a tag")
  end
end
