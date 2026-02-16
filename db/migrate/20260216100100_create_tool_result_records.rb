# frozen_string_literal: true

class CreateToolResultRecords < ActiveRecord::Migration[8.2]
  def change
    create_table :tool_result_records do |t|
      t.string :run_id, null: false
      t.string :tool_call_id, null: false
      t.string :executed_name
      t.jsonb :tool_result, null: false
      t.string :status, null: false, default: "ready"
      t.timestamps
    end

    add_index :tool_result_records, %i[run_id tool_call_id], unique: true
    add_index :tool_result_records, :run_id
  end
end
