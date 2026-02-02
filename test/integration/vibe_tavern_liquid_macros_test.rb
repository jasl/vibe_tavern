require "test_helper"

class VibeTavernLiquidMacrosTest < ActiveSupport::TestCase
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
