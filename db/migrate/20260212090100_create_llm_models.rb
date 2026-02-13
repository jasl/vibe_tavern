# frozen_string_literal: true

class CreateLLMModels < ActiveRecord::Migration[8.2]
  def change
    create_table :llm_models do |t|
      t.references :llm_provider, null: false, foreign_key: true

      t.string :model, null: false
      t.index %i[llm_provider_id model], unique: true

      t.string :name, null: false
      t.string :key, index: { unique: true }

      t.boolean :enabled, null: false, default: false
      t.text :comment

      t.boolean :supports_tool_calling, null: false, default: false
      t.boolean :supports_response_format_json_object, null: false, default: false
      t.boolean :supports_response_format_json_schema, null: false, default: false
      t.boolean :supports_streaming, null: false, default: false
      t.boolean :supports_parallel_tool_calls, null: false, default: false

      t.integer :context_window_tokens, null: false, default: 0
      t.check_constraint "context_window_tokens >= 0", name: "llm_models_context_window_tokens_non_negative"

      t.integer :message_overhead_tokens
      t.check_constraint "message_overhead_tokens IS NULL OR message_overhead_tokens >= 0",
                         name: "llm_models_message_overhead_tokens_non_negative"

      t.datetime :connection_tested_at

      t.timestamps
    end
  end
end
