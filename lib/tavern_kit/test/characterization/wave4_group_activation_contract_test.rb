# frozen_string_literal: true

require "test_helper"

class Wave4GroupActivationContractTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../fixtures/silly_tavern/groups", __dir__)

  def test_activation_strategies_match_st_group_chats
    data = JSON.parse(File.read(File.join(FIXTURES_DIR, "activation_contract.json")))

    Array(data.fetch("cases")).each do |test_case|
      decision = TavernKit::SillyTavern::GroupContext.decide(
        config: test_case.fetch("config"),
        input: test_case.fetch("input"),
      )

      assert_equal(
        Array(test_case.dig("expected", "activated_member_ids")),
        decision.fetch(:activated_member_ids),
        test_case.fetch("name"),
      )
    end
  end
end
