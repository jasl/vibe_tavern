# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Lore::EngineTest < Minitest::Test
  FakeTokenEstimator = Struct.new(:multiplier, keyword_init: true) do
    def estimate(text)
      (text.to_s.length * (multiplier || 1)).to_i
    end
  end

  FixedRng = Struct.new(:value, keyword_init: true) do
    def rand = value.to_f
  end

  def test_selective_logic_modes
    book = load_world_info_fixture("selective_logic.json")
    engine = build_engine

    input1 = build_input(
      books: [book],
      messages: ["magic spell"],
    )
    result1 = engine.scan(input1)
    assert_equal(
      [
        "Magic with any secondary key.",
        "Magic unless all secondary keys are present.",
        "Magic but not dark or evil.",
      ].sort,
      result1.activated_entries.map(&:content).sort,
    )

    input2 = build_input(
      books: [book],
      messages: ["magic dark evil"],
    )
    result2 = engine.scan(input2)
    assert_equal(
      [
        "Magic unless all secondary keys are present.",
        "Magic only when all secondary keys are present.",
      ].sort,
      result2.activated_entries.map(&:content).sort,
    )
  end

  def test_recursive_scanning_activates_entries_from_recurse_buffer
    book = load_world_info_fixture("recursion_settings.json")
    engine = build_engine(recursive_scanning: true, max_recursion_steps: 5)

    input = build_input(
      books: [book],
      messages: ["recursion test delay until recurse"],
    )
    result = engine.scan(input)

    assert_includes result.activated_entries.map(&:content), "This content contains {{recursive keyword}}."
    assert_includes result.activated_entries.map(&:content), "Recursively discovered content."
    assert_includes result.activated_entries.map(&:content), "Only found through recursive scanning."
  end

  def test_exclude_recursion_suppresses_entries_that_only_match_recurse_buffer
    engine = build_engine(recursive_scanning: true, max_recursion_steps: 5)

    starter = entry(
      id: "0",
      keys: ["start"],
      content: "foo is inside recurse buffer",
    )
    excluded = entry(
      id: "1",
      keys: ["foo"],
      content: "should not activate from recursion",
      extensions: { "exclude_recursion" => true },
    )

    book = book(entries: [starter, excluded], world: "test")

    input = build_input(
      books: [book],
      messages: ["start"],
    )
    result = engine.scan(input)

    assert_includes result.activated_entries.map(&:content), "foo is inside recurse buffer"
    refute_includes result.activated_entries.map(&:content), "should not activate from recursion"
  end

  def test_prevent_recursion_stops_entry_content_from_triggering_more_entries
    engine = build_engine(recursive_scanning: true, max_recursion_steps: 5)

    starter = entry(
      id: "0",
      keys: ["start"],
      content: "alpha",
      extensions: { "prevent_recursion" => true },
    )
    would_recurse = entry(
      id: "1",
      keys: ["alpha"],
      content: "bravo",
    )

    book = book(entries: [starter, would_recurse], world: "test")

    input = build_input(
      books: [book],
      messages: ["start"],
    )
    result = engine.scan(input)

    assert_equal ["alpha"], result.activated_entries.map(&:content)
  end

  def test_min_activations_advances_scan_depth
    engine = build_engine(default_scan_depth: 1, recursive_scanning: false)

    shallow = entry(id: "0", keys: ["shallow"], content: "shallow hit")
    deep = entry(id: "1", keys: ["deep"], content: "deep hit")
    book = book(entries: [shallow, deep], world: "test")

    input = TavernKit::SillyTavern::Lore::ScanInput.new(
      messages: ["shallow", "deep"],
      books: [book],
      budget: 10_000,
      min_activations: 2,
      min_activations_depth_max: 2,
      turn_count: 0,
    )
    result = engine.scan(input)

    assert_equal ["deep hit", "shallow hit"].sort, result.activated_entries.map(&:content).sort
  end

  def test_timed_effects_sticky_activates_without_keyword_on_future_turns
    book = load_world_info_fixture("timed_effects.json")
    engine = build_engine
    timed_state = {}

    input1 = TavernKit::SillyTavern::Lore::ScanInput.new(
      messages: ["sticky entry"],
      books: [book],
      budget: 10_000,
      timed_state: timed_state,
      turn_count: 0,
    )
    result1 = engine.scan(input1)
    sticky_entry = result1.activated_entries.find { |e| e.content.include?("sticky effect") }
    assert sticky_entry, "expected sticky entry to activate"
    assert timed_state.key?(sticky_entry.id)

    input2 = TavernKit::SillyTavern::Lore::ScanInput.new(
      messages: ["no match"],
      books: [book],
      budget: 10_000,
      timed_state: timed_state,
      turn_count: 1,
    )
    result2 = engine.scan(input2)
    assert_includes result2.activated_entries.map(&:id), sticky_entry.id
  end

  def test_timed_effects_cooldown_suppresses_activation
    book = load_world_info_fixture("timed_effects.json")
    engine = build_engine
    timed_state = {}

    input1 = TavernKit::SillyTavern::Lore::ScanInput.new(
      messages: ["cooldown entry"],
      books: [book],
      budget: 10_000,
      timed_state: timed_state,
      turn_count: 0,
    )
    result1 = engine.scan(input1)
    cd_entry = result1.activated_entries.find { |e| e.content.include?("cooldown period") }
    assert cd_entry, "expected cooldown entry to activate"

    input2 = TavernKit::SillyTavern::Lore::ScanInput.new(
      messages: ["cooldown entry"],
      books: [book],
      budget: 10_000,
      timed_state: timed_state,
      turn_count: 1,
    )
    result2 = engine.scan(input2)
    refute_includes result2.activated_entries.map(&:id), cd_entry.id
  end

  def test_scan_context_and_scan_injects_are_included_when_enabled
    engine = build_engine

    entry1 = entry(
      id: "0",
      keys: ["from scenario"],
      content: "hit scenario",
      extensions: { "match_scenario" => true },
    )
    entry2 = entry(
      id: "1",
      keys: ["from inject"],
      content: "hit inject",
    )
    book = book(entries: [entry1, entry2], world: "ctx")

    input = TavernKit::SillyTavern::Lore::ScanInput.new(
      messages: ["no match"],
      books: [book],
      budget: 10_000,
      scan_context: { scenario: "from scenario" },
      scan_injects: ["from inject"],
      turn_count: 0,
    )
    result = engine.scan(input)

    assert_includes result.activated_entries.map(&:content), "hit scenario"
    assert_includes result.activated_entries.map(&:content), "hit inject"
  end

  def test_js_regex_conversion_is_cached_for_regex_keys
    buffer = TavernKit::SillyTavern::Lore::Engine::Buffer
    buffer.instance_variable_set(:@js_regex_cache, {})

    calls = 0
    verbose, $VERBOSE = $VERBOSE, nil

    original = ::JsRegexToRuby.method(:try_convert)
    ::JsRegexToRuby.define_singleton_method(:try_convert) do |pattern, literal_only:|
      calls += 1
      original.call(pattern, literal_only: literal_only)
    end

    buffer.match?("hello", "/h.llo/", nil, case_sensitive: false, match_whole_words: false)
    buffer.match?("hello", "/h.llo/", nil, case_sensitive: false, match_whole_words: false)

    assert_equal 1, calls
  ensure
    $VERBOSE = nil
    ::JsRegexToRuby.define_singleton_method(:try_convert, original) if original
    $VERBOSE = verbose
  end

  def test_generation_triggers_and_character_filtering
    engine = build_engine

    trig = entry(
      id: "0",
      keys: ["triggered"],
      content: "trigger ok",
      extensions: { "triggers" => ["continue"] },
    )
    char = entry(
      id: "1",
      keys: ["character only"],
      content: "character ok",
      extensions: { "character_filter_names" => ["Alice"] },
    )
    book = book(entries: [trig, char], world: "filters")

    input1 = TavernKit::SillyTavern::Lore::ScanInput.new(
      messages: ["triggered character only"],
      books: [book],
      budget: 10_000,
      trigger: :normal,
      character_name: "Bob",
      turn_count: 0,
    )
    result1 = engine.scan(input1)
    refute_includes result1.activated_entries.map(&:content), "trigger ok"
    refute_includes result1.activated_entries.map(&:content), "character ok"

    input2 = TavernKit::SillyTavern::Lore::ScanInput.new(
      messages: ["triggered character only"],
      books: [book],
      budget: 10_000,
      trigger: :continue,
      character_name: "Alice",
      turn_count: 0,
    )
    result2 = engine.scan(input2)
    assert_includes result2.activated_entries.map(&:content), "trigger ok"
    assert_includes result2.activated_entries.map(&:content), "character ok"
  end

  def test_inclusion_groups_group_override_and_group_scoring
    rng = FixedRng.new(value: 0.9)
    engine = build_engine(rng: rng, use_group_scoring: true)

    prio = entry(
      id: "0",
      keys: ["hit"],
      content: "prio winner",
      insertion_order: 200,
      extensions: { "group" => "g", "group_override" => true },
    )
    loser = entry(
      id: "1",
      keys: ["hit"],
      content: "prio loser",
      insertion_order: 100,
      extensions: { "group" => "g" },
    )

    score_winner = entry(
      id: "2",
      keys: ["alpha", "beta"],
      content: "score winner",
      insertion_order: 100,
      extensions: { "group" => "h" },
    )
    score_loser = entry(
      id: "3",
      keys: ["alpha"],
      content: "score loser",
      insertion_order: 100,
      extensions: { "group" => "h" },
    )

    book = book(entries: [prio, loser, score_winner, score_loser], world: "groups")

    input = build_input(
      books: [book],
      messages: ["hit alpha beta"],
    )
    result = engine.scan(input)

    assert_includes result.activated_entries.map(&:content), "prio winner"
    refute_includes result.activated_entries.map(&:content), "prio loser"
    assert_includes result.activated_entries.map(&:content), "score winner"
    refute_includes result.activated_entries.map(&:content), "score loser"
  end

  def test_multiple_books_with_same_entry_ids_are_namespaced
    engine = build_engine

    book_a = book(
      entries: [entry(id: "0", keys: ["alpha"], content: "A")],
      world: "A",
    )
    book_b = book(
      entries: [entry(id: "0", keys: ["bravo"], content: "B")],
      world: "B",
    )

    result = engine.scan(build_input(books: [book_a, book_b], messages: ["alpha bravo"]))
    assert_equal ["A", "B"].sort, result.activated_entries.map(&:content).sort
    assert_equal 2, result.activated_entries.map(&:id).uniq.size
  end

  def test_js_regex_literal_keys_match
    engine = build_engine

    e = entry(
      id: "0",
      keys: ["/foo/i"],
      content: "regex hit",
    )
    book = book(entries: [e], world: "regex")

    result = engine.scan(build_input(books: [book], messages: ["FOO"]))
    assert_equal ["regex hit"], result.activated_entries.map(&:content)
  end

  private

  def build_engine(**kwargs)
    TavernKit::SillyTavern::Lore::Engine.new(
      token_estimator: FakeTokenEstimator.new(multiplier: 1),
      **kwargs,
    )
  end

  def load_world_info_fixture(filename)
    raw = TavernKitTest::Fixtures.json("silly_tavern", "world_info", filename)
    TavernKit::SillyTavern::Lore::WorldInfoImporter.load_hash(raw)
  end

  def build_input(books:, messages:, **kwargs)
    TavernKit::SillyTavern::Lore::ScanInput.new(
      messages: messages,
      books: books,
      budget: 10_000,
      **kwargs,
    )
  end

  def entry(id:, keys:, content:, insertion_order: 100, extensions: {})
    TavernKit::Lore::Entry.new(
      id: id,
      keys: keys,
      content: content,
      insertion_order: insertion_order,
      extensions: extensions,
    )
  end

  def book(entries:, world:)
    TavernKit::Lore::Book.new(
      extensions: { "world" => world },
      entries: entries,
    )
  end
end
