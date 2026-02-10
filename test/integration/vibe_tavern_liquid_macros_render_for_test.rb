require "test_helper"

class VibeTavernLiquidMacrosRenderForTest < ActiveSupport::TestCase
  test "render_for wires assigns, variables_store, and context registers" do
    store = TavernKit::VariablesStore::InMemory.new
    store.set("mood", "happy", scope: :local)

    context = TavernKit::PromptBuilder::Context.build({ chat_index: 1, message_index: 5, rng_word: "seed" }, type: :app)

    ctx = TavernKit::PromptBuilder::State.new(context: context, variables_store: store)

    out =
      TavernKit::VibeTavern::LiquidMacros.render_for(
        ctx,
        %(Mood={{ var.mood }} Chat={{ chat_index }} Pick={{ "a,b,c" | pick }}),
      )

    assert_equal "Mood=happy Chat=1 Pick=a", out.strip
  end
end
