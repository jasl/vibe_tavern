# frozen_string_literal: true

require "test_helper"

class RisuaiLoreEngineTest < Minitest::Test
  # Characterization source:
  # resources/Risuai/src/ts/process/lorebook.svelte.ts (loadLoreBookV3Prompt)

  TokenEstimator = Struct.new(:n) do
    def estimate(text, **_kwargs)
      text.to_s.length
    end
  end

  def test_strips_decorators_and_exposes_depth_and_position
    book = TavernKit::Lore::Book.new(
      entries: [
        TavernKit::Lore::Entry.new(
          keys: ["dragon"],
          content: "@@depth 2\nL-DEPTH",
          insertion_order: 100,
          comment: "DEPTH",
        ),
      ]
    )

    engine = TavernKit::RisuAI::Lore::Engine.new(token_estimator: TokenEstimator.new)
    input = TavernKit::RisuAI::Lore::ScanInput.new(messages: ["dragon"], books: [book], budget: nil, scan_depth: 10)

    result = engine.scan(input)

    assert_equal 1, result.activated_entries.size
    entry = result.activated_entries.first
    assert_equal "L-DEPTH", entry.content
    assert_equal "depth", entry.position
    assert_equal 2, entry.extensions.dig("risuai", "depth")
  end

  def test_keep_activate_after_match_sticks_via_chat_var
    vars = TavernKit::ChatVariables::InMemory.new

    book = TavernKit::Lore::Book.new(
      entries: [
        TavernKit::Lore::Entry.new(
          keys: ["dragon"],
          content: "@@keep_activate_after_match\nL-KEEP",
          insertion_order: 100,
          comment: "KEEP",
        ),
      ]
    )

    engine = TavernKit::RisuAI::Lore::Engine.new(token_estimator: TokenEstimator.new)

    first = engine.scan(TavernKit::RisuAI::Lore::ScanInput.new(messages: ["dragon"], books: [book], budget: nil, variables: vars))
    assert_equal ["L-KEEP"], first.activated_entries.map(&:content)

    second = engine.scan(TavernKit::RisuAI::Lore::ScanInput.new(messages: ["no match"], books: [book], budget: nil, variables: vars))
    assert_equal ["L-KEEP"], second.activated_entries.map(&:content)
  end

  def test_dont_activate_after_match_is_one_shot
    vars = TavernKit::ChatVariables::InMemory.new

    book = TavernKit::Lore::Book.new(
      entries: [
        TavernKit::Lore::Entry.new(
          keys: ["dragon"],
          content: "@@dont_activate_after_match\nL-ONESHOT",
          insertion_order: 100,
          comment: "ONESHOT",
        ),
      ]
    )

    engine = TavernKit::RisuAI::Lore::Engine.new(token_estimator: TokenEstimator.new)

    first = engine.scan(TavernKit::RisuAI::Lore::ScanInput.new(messages: ["dragon"], books: [book], budget: nil, variables: vars))
    assert_equal ["L-ONESHOT"], first.activated_entries.map(&:content)

    second = engine.scan(TavernKit::RisuAI::Lore::ScanInput.new(messages: ["dragon"], books: [book], budget: nil, variables: vars))
    assert_equal [], second.activated_entries.map(&:content)
  end

  def test_recursive_scanning_allows_lore_to_trigger_more_lore
    book = TavernKit::Lore::Book.new(
      entries: [
        TavernKit::Lore::Entry.new(
          keys: ["dragon"],
          content: "dragon mentions treasure",
          insertion_order: 200,
          comment: "A",
        ),
        TavernKit::Lore::Entry.new(
          keys: ["treasure"],
          content: "L-TREASURE",
          insertion_order: 100,
          comment: "B",
        ),
      ]
    )

    engine = TavernKit::RisuAI::Lore::Engine.new(token_estimator: TokenEstimator.new)
    input = TavernKit::RisuAI::Lore::ScanInput.new(messages: ["dragon"], books: [book], budget: nil, recursive_scanning: true)

    result = engine.scan(input)

    assert_equal ["L-TREASURE", "dragon mentions treasure"], result.activated_entries.map(&:content).sort
  end

  def test_budget_prefers_higher_priority_and_allows_equal_boundary
    book = TavernKit::Lore::Book.new(
      entries: [
        TavernKit::Lore::Entry.new(
          keys: ["dragon"],
          content: "@@priority 100\nAAAA",
          insertion_order: 100,
          comment: "HIGH",
        ),
        TavernKit::Lore::Entry.new(
          keys: ["dragon"],
          content: "@@priority 10\nBBBBBBBB",
          insertion_order: 90,
          comment: "LOW",
        ),
      ]
    )

    engine = TavernKit::RisuAI::Lore::Engine.new(token_estimator: TokenEstimator.new)
    input = TavernKit::RisuAI::Lore::ScanInput.new(messages: ["dragon"], books: [book], budget: 4, scan_depth: 10)

    result = engine.scan(input)

    assert_equal ["AAAA"], result.activated_entries.map(&:content)
  end

  def test_inject_lore_appends_to_target_and_is_removed
    book = TavernKit::Lore::Book.new(
      entries: [
        TavernKit::Lore::Entry.new(
          keys: ["dragon"],
          content: "BASE",
          insertion_order: 100,
          comment: "TARGET",
        ),
        TavernKit::Lore::Entry.new(
          keys: ["dragon"],
          content: "@@inject_lore TARGET\nINJECTED",
          insertion_order: 90,
          comment: "INJECT",
        ),
      ]
    )

    engine = TavernKit::RisuAI::Lore::Engine.new(token_estimator: TokenEstimator.new)
    input = TavernKit::RisuAI::Lore::ScanInput.new(messages: ["dragon"], books: [book], budget: nil, scan_depth: 10)

    result = engine.scan(input)

    assert_equal 1, result.activated_entries.size
    assert_equal "BASE INJECTED", result.activated_entries.first.content
  end
end
