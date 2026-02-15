# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::Skills::StoreTest < Minitest::Test
  def setup
    @store = AgentCore::Resources::Skills::Store.new
  end

  def test_list_skills_raises_not_implemented
    assert_raises(AgentCore::NotImplementedError) { @store.list_skills }
  end

  def test_load_skill_raises_not_implemented
    assert_raises(AgentCore::NotImplementedError) { @store.load_skill(name: "test") }
  end

  def test_read_skill_file_raises_not_implemented
    assert_raises(AgentCore::NotImplementedError) do
      @store.read_skill_file(name: "test", rel_path: "scripts/a.sh", max_bytes: 1000)
    end
  end

  def test_read_skill_file_bytes_raises_not_implemented
    assert_raises(AgentCore::NotImplementedError) do
      @store.read_skill_file_bytes(name: "test", rel_path: "scripts/a.sh", max_bytes: 1000)
    end
  end
end
