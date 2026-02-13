# frozen_string_literal: true

class CreateLLMPresets < ActiveRecord::Migration[8.2]
  def change
    create_table :llm_presets do |t|
      t.references :llm_model, null: false, foreign_key: true

      t.string :key
      t.index  %i[llm_model_id key], unique: true, where: "key IS NOT NULL"

      t.string :name, null: false
      t.text :comment

      t.jsonb :llm_options_overrides, null: false, default: {}

      t.timestamps
    end
  end
end
