# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::Memory::InMemoryTest < Minitest::Test
  def setup
    @memory = AgentCore::Resources::Memory::InMemory.new
  end

  def test_store_and_search
    @memory.store(content: "The sky is blue", metadata: { source: "facts" })
    @memory.store(content: "Cats are pets", metadata: { source: "facts" })

    results = @memory.search(query: "sky")
    assert_equal 1, results.size
    assert_equal "The sky is blue", results.first.content
    assert results.first.score
  end

  def test_search_case_insensitive
    @memory.store(content: "Ruby is great")
    results = @memory.search(query: "RUBY")
    assert_equal 1, results.size
  end

  def test_search_with_limit
    5.times { |i| @memory.store(content: "item #{i}") }
    results = @memory.search(query: "item", limit: 3)
    assert_equal 3, results.size
  end

  def test_search_with_metadata_filter
    @memory.store(content: "apple", metadata: { category: "fruit" })
    @memory.store(content: "apple sauce", metadata: { category: "recipe" })

    results = @memory.search(query: "apple", metadata_filter: { category: "fruit" })
    assert_equal 1, results.size
    assert_equal "fruit", results.first.metadata[:category]
  end

  def test_forget
    entry = @memory.store(content: "forget me")
    assert_equal 1, @memory.size

    assert @memory.forget(id: entry.id)
    assert_equal 0, @memory.size
  end

  def test_forget_nonexistent
    refute @memory.forget(id: "nonexistent")
  end

  def test_all
    @memory.store(content: "a")
    @memory.store(content: "b")
    assert_equal 2, @memory.all.size
  end

  def test_clear
    @memory.store(content: "x")
    @memory.clear
    assert_equal 0, @memory.size
  end
end
