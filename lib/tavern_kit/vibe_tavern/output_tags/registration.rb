# frozen_string_literal: true

require_relative "sanitizers/lang_spans"

module TavernKit
  module VibeTavern
    module OutputTags
      module Registration
        TavernKit.on_load(:vibe_tavern, id: :"vibe_tavern.output_tags.lang_spans") do |infra|
          registry = infra.output_tags_registry
          registry.register_sanitizer(:lang_spans, TavernKit::VibeTavern::OutputTags::Sanitizers::LangSpans)
        end
      end
    end
  end
end
