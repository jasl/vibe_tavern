# frozen_string_literal: true

require "test_helper"

class Wave4GroupActivationContractTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../fixtures/silly_tavern/groups", __dir__)

  def pending!(reason)
    skip("Pending Wave 4 (GroupContext activation): #{reason}")
  end

  def test_activation_strategies_match_st_group_chats
    pending!("GroupContext decision algorithm must match ST staging group-chats.js")

    data = JSON.parse(File.read(File.join(FIXTURES_DIR, "activation_contract.json")))

    # Contract summary (see docs/rewrite/wave4-contracts.md):
    # - LIST: enabled members in list order
    # - NATURAL: mention parsing (extractAllWords) + talkativeness roll + fallback
    # - POOLED: select member who has not spoken since last user message (or random fallback)
    #
    # Determinism:
    # - RNG must be seedable so app-provided decisions can be recomputed and compared.
    _ = data
  end
end
