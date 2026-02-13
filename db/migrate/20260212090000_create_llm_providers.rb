# frozen_string_literal: true

class CreateLLMProviders < ActiveRecord::Migration[8.2]
  def change
    create_table :llm_providers do |t|
      t.string :name, null: false, index: { unique: true }

      t.string :api_format, null: false, default: "openai"
      t.string :base_url, null: false
      t.string :api_prefix, null: false
      t.text :api_key
      t.jsonb :headers, null: false, default: {}
      t.jsonb :llm_options_defaults, null: false, default: {}

      t.integer :message_overhead_tokens, null: false, default: 0
      t.check_constraint "message_overhead_tokens >= 0", name: "llm_providers_message_overhead_tokens_non_negative"

      t.timestamps
    end
  end
end
