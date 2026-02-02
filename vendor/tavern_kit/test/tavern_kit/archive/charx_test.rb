# frozen_string_literal: true

require "test_helper"
require "zip"

class TavernKit::Archive::CharXTest < Minitest::Test
  def charx_bytes(card_hash:, assets: {})
    Zip::OutputStream.write_buffer do |out|
      out.put_next_entry("card.json")
      out.write(JSON.generate(card_hash))

      assets.each do |path, content|
        out.put_next_entry(path)
        out.write(content)
      end
    end.string
  end

  def test_loads_ccv3_card_and_exposes_embedded_asset_paths
    card_hash = TavernKit::CharacterCard.export_v3(TavernKit::Character.create(name: "Alice"))
    card_hash["data"]["assets"] = [
      { "type" => "icon", "uri" => "embeded://assets/icon.png", "name" => "main", "ext" => "png" },
    ]

    data = charx_bytes(
      card_hash: card_hash,
      assets: { "assets/icon.png" => "PNGDATA" },
    )

    TavernKit::Archive::CharX.open(data) do |pkg|
      assert_equal card_hash, pkg.card_hash
      assert_equal ["assets/icon.png"], pkg.embedded_asset_paths
      assert_includes pkg.entry_paths, "assets/icon.png"
      assert_equal "PNGDATA", pkg.read_asset("assets/icon.png")

      character = pkg.character
      assert_equal "Alice", character.name
      assert character.v3?
    end
  end
end
