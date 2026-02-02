require "test_helper"

class VibeTavernUserInputPreprocessorTest < ActiveSupport::TestCase
  test "is disabled by default (no runtime toggle and no explicit enabled)" do
    store = TavernKit::VariablesStore::InMemory.new
    store.set("mood", "happy", scope: :local)

    out =
      TavernKit::VibeTavern::UserInputPreprocessor.call(
        "{{ var.mood }}",
        variables_store: store,
      )

    assert_equal "{{ var.mood }}", out
  end

  test "runs Liquid macros when enabled explicitly" do
    store = TavernKit::VariablesStore::InMemory.new
    store.set("mood", "happy", scope: :local)

    out =
      TavernKit::VibeTavern::UserInputPreprocessor.call(
        "{{ var.mood }}",
        variables_store: store,
        enabled: true,
      )

    assert_equal "happy", out
  end

  test "passes runtime through to filters via registers" do
    store = TavernKit::VariablesStore::InMemory.new
    runtime = TavernKit::Runtime::Base.build({ message_index: 5, rng_word: "seed" }, type: :app)

    out =
      TavernKit::VibeTavern::UserInputPreprocessor.call(
        %({{ "a,b,c" | pick }}),
        variables_store: store,
        enabled: true,
        runtime: runtime,
      )

    assert_equal "a", out.strip
  end

  test "uses runtime toggles to enable preprocessing" do
    store = TavernKit::VariablesStore::InMemory.new
    store.set("mood", "happy", scope: :local)

    runtime = TavernKit::Runtime::Base.build({ toggles: { expand_user_input_macros: true } }, type: :app)

    out =
      TavernKit::VibeTavern::UserInputPreprocessor.call(
        "{{ var.mood }}",
        variables_store: store,
        runtime: runtime,
      )

    assert_equal "happy", out
  end

  test "does not enable preprocessing when runtime toggles keys are not normalized (string/camelCase keys)" do
    store = TavernKit::VariablesStore::InMemory.new
    store.set("mood", "happy", scope: :local)

    runtime = TavernKit::Runtime::Base.build({ toggles: { "expand_user_input_macros" => true, "expandUserInputMacros" => true } }, type: :app)

    out =
      TavernKit::VibeTavern::UserInputPreprocessor.call(
        "{{ var.mood }}",
        variables_store: store,
        runtime: runtime,
      )

    assert_equal "{{ var.mood }}", out
  end

  test "does not explode on template errors in tolerant mode (passthrough)" do
    store = TavernKit::VariablesStore::InMemory.new

    out =
      TavernKit::VibeTavern::UserInputPreprocessor.call(
        "{% this_is_not_a_real_tag %}",
        variables_store: store,
        enabled: true,
        strict: false,
        on_error: :passthrough,
      )

    assert_equal "{% this_is_not_a_real_tag %}", out
  end
end
