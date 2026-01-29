# frozen_string_literal: true

module TavernKit
  module Lore
    Result = Data.define(
      :activated_entries, # Array<Lore::Entry>
      :total_tokens,      # Integer
      :trim_report        # TrimReport, nil
    )
  end
end
