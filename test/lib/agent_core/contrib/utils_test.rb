# frozen_string_literal: true

require "test_helper"

class AgentCoreContribUtilsTest < ActiveSupport::TestCase
  test "deep_merge_hashes merges recursively and right wins" do
    left = { a: 1, b: { c: 1, d: [1] } }
    right = { b: { c: 2, d: [2], e: 3 }, f: 9 }

    merged = AgentCore::Contrib::Utils.deep_merge_hashes(left, right)

    assert_equal({ a: 1, b: { c: 2, d: [2], e: 3 }, f: 9 }, merged)
  end

  test "deep_merge_hashes accepts many inputs" do
    merged = AgentCore::Contrib::Utils.deep_merge_hashes({ a: 1 }, { b: 2 }, { a: 3 })
    assert_equal({ a: 3, b: 2 }, merged)
  end

  test "deep_merge_hashes treats non-hash inputs as empty" do
    merged = AgentCore::Contrib::Utils.deep_merge_hashes({ a: 1 }, "nope", nil, { b: 2 })
    assert_equal({ a: 1, b: 2 }, merged)
  end
end
