require "test_helper"

class VibeTavernLiquidMacrosTest < ActiveSupport::TestCase
  test "configures Liquid resource limits and guards against oversized templates" do
    env = TavernKit::VibeTavern::LiquidMacros.environment
    assert_equal TavernKit::VibeTavern::LiquidMacros::DEFAULT_RESOURCE_LIMITS, env.default_resource_limits

    big = "a" * (TavernKit::VibeTavern::LiquidMacros::MAX_TEMPLATE_BYTES + 1)

    out = TavernKit::VibeTavern::LiquidMacros.render(big)
    assert_equal big, out

    assert_raises(::Liquid::Error) do
      TavernKit::VibeTavern::LiquidMacros.render(big, strict: true)
    end
  end

  test "strict mode raises on undefined variables and filters" do
    assert_raises(::Liquid::Error) do
      TavernKit::VibeTavern::LiquidMacros.render("{{ missing }}", strict: true)
    end

    assert_raises(::Liquid::Error) do
      TavernKit::VibeTavern::LiquidMacros.render(%({{ "a" | missing_filter }}), strict: true)
    end
  end

  test "reads variables through var/global drops" do
    store = TavernKit::VariablesStore::InMemory.new
    store.set("mood", "happy", scope: :local)
    store.set("score", 10, scope: :global)

    out = TavernKit::VibeTavern::LiquidMacros.render("{{ var.mood }} {{ global.score }}", variables_store: store)
    assert_equal "happy 10", out.strip
  end

  test "supports bracket access for non-identifier keys" do
    store = TavernKit::VariablesStore::InMemory.new
    store.set("some-key", "x", scope: :local)

    out = TavernKit::VibeTavern::LiquidMacros.render(%({{ var["some-key"] }}), variables_store: store)
    assert_equal "x", out.strip
  end

  test "supports ST-style escaped braces" do
    store = TavernKit::VariablesStore::InMemory.new
    store.set("mood", "happy", scope: :local)

    out = TavernKit::VibeTavern::LiquidMacros.render(%(\\{\\{ var.mood \\}\\}), variables_store: store)
    assert_equal "{{ var.mood }}", out.strip
  end

  test "strips whitespace-only blank lines" do
    out = TavernKit::VibeTavern::LiquidMacros.render("a\n  \n\t\nb")
    assert_equal "a\n\n\nb", out
  end

  test "setvar tag writes to local variables store" do
    store = TavernKit::VariablesStore::InMemory.new

    out = TavernKit::VibeTavern::LiquidMacros.render(%({% setvar mood = "happy" %}{{ var.mood }}), variables_store: store)
    assert_equal "happy", out.strip
    assert_equal "happy", store.get("mood", scope: :local)
  end

  test "addvar is numeric when possible, otherwise concatenates" do
    store = TavernKit::VariablesStore::InMemory.new

    store.set("score", "1", scope: :local)
    out = TavernKit::VibeTavern::LiquidMacros.render(%({% addvar score = 2 %}{{ var.score }}), variables_store: store)
    assert_equal "3", out.strip

    store.set("s", "a", scope: :local)
    out = TavernKit::VibeTavern::LiquidMacros.render(%({% addvar s = "b" %}{{ var.s }}), variables_store: store)
    assert_equal "ab", out.strip
  end

  test "inc/dec/delete tags operate on variables store" do
    store = TavernKit::VariablesStore::InMemory.new

    out = TavernKit::VibeTavern::LiquidMacros.render(%({% incvar turns %}{{ var.turns }}), variables_store: store)
    assert_equal "1", out.strip

    out = TavernKit::VibeTavern::LiquidMacros.render(%({% decvar turns %}{{ var.turns }}), variables_store: store)
    assert_equal "0", out.strip

    out = TavernKit::VibeTavern::LiquidMacros.render(%({% deletevar turns %}{{ var.turns }}), variables_store: store)
    assert_equal "", out.strip
  end

  test "setdefaultvar writes only when missing" do
    store = TavernKit::VariablesStore::InMemory.new

    out = TavernKit::VibeTavern::LiquidMacros.render(%({% setdefaultvar mood = "happy" %}{{ var.mood }}), variables_store: store)
    assert_equal "happy", out.strip

    out = TavernKit::VibeTavern::LiquidMacros.render(%({% setdefaultvar mood = "sad" %}{{ var.mood }}), variables_store: store)
    assert_equal "happy", out.strip
  end

  test "global tags write to global scope and read through global drop" do
    store = TavernKit::VariablesStore::InMemory.new

    out = TavernKit::VibeTavern::LiquidMacros.render(%({% setglobal score = 10 %}{{ global.score }}), variables_store: store)
    assert_equal "10", out.strip

    out = TavernKit::VibeTavern::LiquidMacros.render(%({% incglobal score %}{{ global.score }}), variables_store: store)
    assert_equal "11", out.strip

    out = TavernKit::VibeTavern::LiquidMacros.render(%({% deleteglobal score %}{{ global.score }}), variables_store: store)
    assert_equal "", out.strip
  end
end
