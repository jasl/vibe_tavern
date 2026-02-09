# frozen_string_literal: true

require_relative "output_tags"

module TavernKit
  module VibeTavern
    class Infrastructure
      attr_reader :output_tags_registry

      def initialize(output_tags_registry:)
        @output_tags_registry = output_tags_registry
      end
    end

    class << self
      def infrastructure
        @infrastructure ||=
          Infrastructure.new(
            output_tags_registry: TavernKit::VibeTavern::OutputTags.registry,
          )
      end
    end
  end
end
