# frozen_string_literal: true

class CreateReportsAndReportRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :reports do |t|
      t.string :name, null: false
      t.integer :mode, null: false, default: 0
      t.string :file
      t.text :source
      t.string :predicate, null: false
      t.string :engine, null: false, default: "auto"
      t.boolean :trusted, null: false, default: false
      t.boolean :allow_imports, null: false, default: false
      t.json :flags_schema, null: false, default: {}
      t.json :default_flags, null: false, default: {}
      t.timestamps
    end

    add_index :reports, :mode
    add_index :reports, :name

    create_table :report_runs do |t|
      t.references :report, null: false, foreign_key: true
      t.string :status, null: false
      t.integer :duration_ms
      t.integer :row_count
      t.string :sql_digest
      t.string :error_class
      t.text :error_message
      t.datetime :created_at, null: false
    end

    add_index :report_runs, :created_at
  end
end
