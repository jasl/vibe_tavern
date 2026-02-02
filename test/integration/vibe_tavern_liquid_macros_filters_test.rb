require "test_helper"

class VibeTavernLiquidMacrosFiltersTest < ActiveSupport::TestCase
  test "hash7 returns a stable 7-digit string" do
    out = TavernKit::VibeTavern::LiquidMacros.render(%({{ "hello" | hash7 }}))
    assert_equal 7, out.strip.length
    assert_match(/\A\d{7}\z/, out.strip)

    out2 = TavernKit::VibeTavern::LiquidMacros.render(%({{ "hello" | hash7 }}))
    assert_equal out.strip, out2.strip

    out3 = TavernKit::VibeTavern::LiquidMacros.render(%({{ "hello" | hash }}))
    assert_equal out.strip, out3.strip
  end

  test "pick chooses deterministically based on runtime message_index + rng_word" do
    runtime = TavernKit::Runtime::Base.build({ message_index: 5, rng_word: "seed" }, type: :app)
    ctx = TavernKit::Prompt::Context.new(runtime: runtime)
    assigns = TavernKit::VibeTavern::LiquidMacros::Assigns.build(ctx)

    out =
      TavernKit::VibeTavern::LiquidMacros.render(
        %({{ "a,b,c" | pick }}),
        assigns: assigns,
      )

    # Deterministic expected value (pinned by this test).
    assert_equal "a", out.strip
  end

  test "pick works on array input and supports escaped commas" do
    runtime = TavernKit::Runtime::Base.build({ message_index: 1, rng_word: "seed" }, type: :app)
    assigns = { "runtime" => { "message_index" => 1, "rng_word" => "seed" } }

    out =
      TavernKit::VibeTavern::LiquidMacros.render(
        %({{ "a,\\,b,c" | pick }}),
        assigns: assigns,
      )

    assert_includes ["a", ",b", "c"], out.strip

    out =
      TavernKit::VibeTavern::LiquidMacros.render(
        %({{ "a,b,c" | split: "," | pick }}),
        assigns: assigns,
      )

    assert_includes ["a", "b", "c"], out.strip
  end

  test "rollp is deterministic and uses runtime seeds" do
    runtime = TavernKit::Runtime::Base.build({ message_index: 5, rng_word: "seed" }, type: :app)
    assigns = { "runtime" => { "message_index" => 5, "rng_word" => "seed" } }

    out =
      TavernKit::VibeTavern::LiquidMacros.render(
        %({{ "2d6" | rollp }}),
        assigns: assigns,
      )

    assert_equal "7", out.strip
  end

  test "time helpers can be made deterministic via runtime.now_ms" do
    assigns = { "runtime" => { "now_ms" => 1_700_000_000_000 } }

    out = TavernKit::VibeTavern::LiquidMacros.render(%({{ runtime.now_ms | unixtime }}), assigns: assigns)
    assert_equal "1700000000", out.strip

    out = TavernKit::VibeTavern::LiquidMacros.render(%({{ runtime.now_ms | isodate }}), assigns: assigns)
    assert_equal "2023-11-14", out.strip

    out = TavernKit::VibeTavern::LiquidMacros.render(%({{ runtime.now_ms | isotime }}), assigns: assigns)
    assert_equal "22:13:20", out.strip

    out =
      TavernKit::VibeTavern::LiquidMacros.render(
        %({{ runtime.now_ms | datetimeformat: "YYYY-MM-DD HH:mm:ss" }}),
        assigns: assigns,
      )
    assert_equal "2023-11-14 22:13:20", out.strip
  end
end
