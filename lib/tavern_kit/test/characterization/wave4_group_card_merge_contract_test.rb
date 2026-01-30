# frozen_string_literal: true

require "test_helper"

class Wave4GroupCardMergeContractTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../fixtures/silly_tavern/groups", __dir__)

  def pending!(reason)
    skip("Pending Wave 4 (GroupContext card merge): #{reason}")
  end

  def test_append_modes_merge_cards_like_st
    pending!("Group card merging must match ST generation_mode join behavior")

    data = JSON.parse(File.read(File.join(FIXTURES_DIR, "card_merge_contract.json")))

    # Contract summary (ST staging public/scripts/group-chats.js#getGroupCharacterCardsLazy):
    # - APPEND skips disabled members (unless current speaker)
    # - APPEND_DISABLED includes disabled members
    # - join_prefix/join_suffix apply per member value and support <FIELDNAME>
    # - example messages add <START>\\n when missing
    _ = data
  end
end
