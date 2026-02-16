# frozen_string_literal: true

class CreateContinuationRecords < ActiveRecord::Migration[8.2]
  def change
    create_table :continuation_records do |t|
      t.string :run_id, null: false
      t.string :continuation_id, null: false
      t.string :parent_continuation_id
      t.references :llm_model, null: false, foreign_key: true
      t.string :tooling_key, null: false
      t.string :status, null: false, default: "current"
      t.jsonb :payload, null: false
      t.datetime :consumed_at
      t.timestamps
    end

    add_index :continuation_records, %i[run_id continuation_id], unique: true
    add_index :continuation_records, :run_id, unique: true, where: "status = 'current'"
    add_index :continuation_records, :status

    add_check_constraint :continuation_records, "status in ('current','consumed')", name: "continuation_records_status_check"
  end
end
