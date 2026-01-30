# frozen_string_literal: true

require "test_helper"

class TavernKit::TrimmerTest < Minitest::Test
  class StaticEstimator
    def estimate(text, model_hint: nil)
      Integer(text)
    end
  end

  def build_block(id:, tokens:, budget_group:, role: :system, removable: true, priority: 100, metadata: {})
    TavernKit::Prompt::Block.new(
      id: id,
      role: role,
      content: tokens.to_s,
      removable: removable,
      token_budget_group: budget_group,
      priority: priority,
      metadata: metadata,
    )
  end

  def test_group_order_evicts_examples_then_lore_then_history
    blocks = [
      build_block(id: "sys", tokens: 50, budget_group: :system, removable: false),
      build_block(id: "ex1_a", tokens: 30, budget_group: :examples, metadata: { eviction_bundle: "ex1" }),
      build_block(id: "ex1_b", tokens: 30, budget_group: :examples, metadata: { eviction_bundle: "ex1" }),
      build_block(id: "lore1", tokens: 40, budget_group: :lore),
      build_block(id: "h1_user", tokens: 20, budget_group: :history, role: :user),
      build_block(id: "h1_asst", tokens: 20, budget_group: :history, role: :assistant),
      build_block(id: "h2_user", tokens: 20, budget_group: :history, role: :user),
    ]

    result = TavernKit::Trimmer.trim(
      blocks,
      strategy: :group_order,
      budget_tokens: 130,
      token_estimator: StaticEstimator.new,
    )

    trimmed = TavernKit::Trimmer.apply(blocks, result)

    assert_equal false, trimmed.find { |b| b.id == "ex1_a" }.enabled?
    assert_equal false, trimmed.find { |b| b.id == "ex1_b" }.enabled?
    assert_equal false, trimmed.find { |b| b.id == "lore1" }.enabled?

    assert_equal true, trimmed.find { |b| b.id == "h1_user" }.enabled?
    assert_equal true, trimmed.find { |b| b.id == "h2_user" }.enabled?

    assert_equal 3, result.report.eviction_count
    assert_equal :group_order, result.report.strategy
    assert_equal 210, result.report.initial_tokens
    assert_equal 110, result.report.final_tokens

    ex_reasons = result.report.evictions.select { |e| e.budget_group == :examples }.map(&:reason).uniq
    assert_equal [:group_overflow], ex_reasons

    lore_reason = result.report.evictions.find { |e| e.budget_group == :lore }.reason
    assert_equal :budget_exceeded, lore_reason
  end

  def test_group_order_preserves_latest_user_message_in_history
    blocks = [
      build_block(id: "sys", tokens: 10, budget_group: :system, removable: false),
      build_block(id: "h_old_user", tokens: 10, budget_group: :history, role: :user),
      build_block(id: "h_old_asst", tokens: 10, budget_group: :history, role: :assistant),
      build_block(id: "h_latest_user", tokens: 10, budget_group: :history, role: :user),
    ]

    result = TavernKit::Trimmer.trim(
      blocks,
      strategy: :group_order,
      budget_tokens: 25,
      token_estimator: StaticEstimator.new,
    )

    trimmed = TavernKit::Trimmer.apply(blocks, result)

    assert_equal false, trimmed.find { |b| b.id == "h_old_user" }.enabled?
    assert_equal false, trimmed.find { |b| b.id == "h_old_asst" }.enabled?
    assert_equal true, trimmed.find { |b| b.id == "h_latest_user" }.enabled?
  end

  def test_priority_evicts_lowest_priority_first
    blocks = [
      build_block(id: "sys", tokens: 10, budget_group: :system, removable: false, priority: 0),
      build_block(id: "p1", tokens: 10, budget_group: :custom, priority: 10),
      build_block(id: "p2", tokens: 10, budget_group: :custom, priority: 20),
      build_block(id: "p3", tokens: 10, budget_group: :custom, priority: 30),
    ]

    result = TavernKit::Trimmer.trim(
      blocks,
      strategy: :priority,
      budget_tokens: 30,
      token_estimator: StaticEstimator.new,
    )

    trimmed = TavernKit::Trimmer.apply(blocks, result)
    assert_equal false, trimmed.find { |b| b.id == "p1" }.enabled?
    assert_equal true, trimmed.find { |b| b.id == "p2" }.enabled?
    assert_equal true, trimmed.find { |b| b.id == "p3" }.enabled?

    assert_equal [:priority_cutoff], result.report.evictions.map(&:reason).uniq
  end

  def test_raises_when_mandatory_blocks_exceed_budget
    blocks = [
      build_block(id: "sys", tokens: 50, budget_group: :system, removable: false),
      build_block(id: "required", tokens: 60, budget_group: :history, removable: false, role: :user),
    ]

    assert_raises(TavernKit::MaxTokensExceededError) do
      TavernKit::Trimmer.trim(
        blocks,
        strategy: :group_order,
        max_tokens: 80,
        reserve_tokens: 0,
        token_estimator: StaticEstimator.new,
        stage: :trimming,
      )
    end
  end
end
