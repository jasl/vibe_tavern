# frozen_string_literal: true

require "test_helper"

class TavernKit::TrimReportTest < Minitest::Test
  def test_trim_report_helpers
    eviction = TavernKit::EvictionRecord.new(
      block_id: "b1",
      slot: :lore,
      token_count: 10,
      reason: :budget_exceeded,
      budget_group: :lore,
      priority: 50,
      source: { stage: :lore, id: "wi:1" },
    )

    report = TavernKit::TrimReport.new(
      strategy: :group_order,
      budget_tokens: 100,
      initial_tokens: 130,
      final_tokens: 95,
      eviction_count: 1,
      evictions: [eviction],
    )

    assert_equal 35, report.tokens_saved
    assert report.over_budget?

    result = TavernKit::TrimResult.new(
      kept: [],
      evicted: [],
      report: report,
    )

    assert_equal report, result.report
  end
end
