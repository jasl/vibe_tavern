# frozen_string_literal: true

require "json"

module TavernKit
  module Ingest
    module Json
      module_function

      def call(path)
        hash = ::JSON.parse(::File.read(path))
        character = TavernKit::CharacterCard.load_hash(hash)
        Bundle.new(character: character)
      end
    end
  end
end
