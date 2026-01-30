# frozen_string_literal: true

require "test_helper"

class Wave4TrimmerContractTest < Minitest::Test
  def pending!(reason)
    skip("Pending Wave 4 (Trimmer): #{reason}")
  end

  class CharEstimator
    def estimate(text, model_hint: nil)
      text.to_s.length
    end
  end

  def test_group_order_examples_evicted_as_bundles
    pending!("examples blocks sharing metadata[:eviction_bundle] must be enabled/disabled together")

    estimator = CharEstimator.new

    blocks = [
      TavernKit::Prompt::Block.new(
        role: :user,
        content: "ex1-u",
        token_budget_group: :examples,
        metadata: { eviction_bundle: "ex1" },
      ),
      TavernKit::Prompt::Block.new(
        role: :assistant,
        content: "ex1-a",
        token_budget_group: :examples,
        metadata: { eviction_bundle: "ex1" },
      ),
      TavernKit::Prompt::Block.new(
        role: :user,
        content: "ex2-u",
        token_budget_group: :examples,
        metadata: { eviction_bundle: "ex2" },
      ),
      TavernKit::Prompt::Block.new(
        role: :assistant,
        content: "ex2-a",
        token_budget_group: :examples,
        metadata: { eviction_bundle: "ex2" },
      ),
    ]

    trimmer = TavernKit::Trimmer.new(strategy: :group_order)

    # Only enough budget for one dialogue.
    result = trimmer.trim(blocks, budget: 10, estimator: estimator)

    bundle1_enabled = result.kept.any? { |b| b.metadata[:eviction_bundle] == "ex1" }
    bundle2_enabled = result.kept.any? { |b| b.metadata[:eviction_bundle] == "ex2" }

    # Exactly one bundle should remain.
    assert_equal 1, [bundle1_enabled, bundle2_enabled].count(true)

    # If a bundle is evicted, both of its blocks must be evicted.
    evicted_bundles = result.evicted.group_by { |b| b.metadata[:eviction_bundle] }
    evicted_bundles.each_value do |bundle_blocks|
      assert_equal 2, bundle_blocks.size
    end
  end

  def test_group_order_preserves_latest_user_message
    pending!("history trimming must preserve the latest user message")

    estimator = CharEstimator.new

    blocks = [
      TavernKit::Prompt::Block.new(role: :user, content: "u1", token_budget_group: :history),
      TavernKit::Prompt::Block.new(role: :assistant, content: "a1", token_budget_group: :history),
      TavernKit::Prompt::Block.new(role: :user, content: "u2", token_budget_group: :history),
    ]

    trimmer = TavernKit::Trimmer.new(strategy: :group_order)

    # Budget small enough that at least one history block must be evicted.
    result = trimmer.trim(blocks, budget: 2, estimator: estimator)

    latest_user = blocks.last
    refute_includes result.evicted.map(&:id), latest_user.id
  end
end
