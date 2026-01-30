# frozen_string_literal: true

require "test_helper"

class Wave4TrimmerContractTest < Minitest::Test
  class CharEstimator
    def estimate(text, model_hint: nil)
      text.to_s.length
    end
  end

  def test_group_order_examples_evicted_as_bundles
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

    # Only enough budget for one dialogue.
    result = TavernKit::Trimmer.trim(
      blocks,
      strategy: :group_order,
      budget_tokens: 10,
      token_estimator: estimator,
    )

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
    estimator = CharEstimator.new

    blocks = [
      TavernKit::Prompt::Block.new(role: :user, content: "u1", token_budget_group: :history),
      TavernKit::Prompt::Block.new(role: :assistant, content: "a1", token_budget_group: :history),
      TavernKit::Prompt::Block.new(role: :user, content: "u2", token_budget_group: :history),
    ]

    # Budget small enough that at least one history block must be evicted.
    result = TavernKit::Trimmer.trim(
      blocks,
      strategy: :group_order,
      budget_tokens: 2,
      token_estimator: estimator,
    )

    latest_user = blocks.last
    refute_includes result.evicted.map(&:id), latest_user.id
  end

  def test_trimming_failure_raises_max_tokens_exceeded_error
    estimator = CharEstimator.new

    blocks = [
      TavernKit::Prompt::Block.new(
        role: :system,
        content: "mandatory",
        removable: false,
        token_budget_group: :system,
      ),
    ]

    error = assert_raises(TavernKit::MaxTokensExceededError) do
      TavernKit::Trimmer.trim(
        blocks,
        strategy: :group_order,
        max_tokens: 10,
        reserve_tokens: 9,
        token_estimator: estimator,
        stage: :trimming,
      )
    end

    assert_equal :trimming, error.stage
    assert_operator error.estimated_tokens, :>, error.limit_tokens
  end
end
