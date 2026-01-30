# frozen_string_literal: true

require "test_helper"

class Wave4GroupCardMergeContractTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../fixtures/silly_tavern/groups", __dir__)

  def test_append_modes_merge_cards_like_st
    data = JSON.parse(File.read(File.join(FIXTURES_DIR, "card_merge_contract.json")))

    Array(data.fetch("cases")).each do |test_case|
      characters_by_id = test_case.fetch("characters").each_with_object({}) do |(id, attrs), map|
        map[id] = TavernKit::Character.create(
          name: attrs.fetch("name"),
          description: attrs.fetch("description"),
          personality: attrs.fetch("personality"),
          scenario: attrs.fetch("scenario"),
          mes_example: attrs.fetch("mes_examples"),
        )
      end

      merged = TavernKit::SillyTavern::GroupContext.merge_cards(
        config: test_case.fetch("config"),
        characters_by_id: characters_by_id,
        current_speaker_id: test_case.fetch("current_speaker_id"),
        overrides: test_case.fetch("overrides"),
      )

      expected = test_case.fetch("expected")
      assert_equal expected.fetch("description"), merged.fetch(:description), test_case.fetch("name")
      assert_equal expected.fetch("personality"), merged.fetch(:personality), test_case.fetch("name")
      assert_equal expected.fetch("scenario"), merged.fetch(:scenario), test_case.fetch("name")
      assert_equal expected.fetch("mesExamples"), merged.fetch(:mesExamples), test_case.fetch("name")
    end
  end
end
