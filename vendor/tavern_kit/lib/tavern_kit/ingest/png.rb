# frozen_string_literal: true

module TavernKit
  module Ingest
    module Png
      module_function

      def call(path)
        hash = TavernKit::Png::Parser.extract_card_payload(path)
        character = TavernKit::CharacterCard.load_hash(hash)

        # For PNG/APNG, keep referencing the original input path.
        Bundle.new(character: character, main_image_path: path)
      end
    end
  end
end
