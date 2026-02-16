# frozen_string_literal: true

class AddConsumingToContinuationRecords < ActiveRecord::Migration[8.2]
  def change
    add_column :continuation_records, :consuming_at, :datetime
    add_column :continuation_records, :resume_lock_token, :string
    add_column :continuation_records, :resume_attempts, :integer, null: false, default: 0
    add_column :continuation_records, :last_resume_error_class, :string
    add_column :continuation_records, :last_resume_error_message, :text
    add_column :continuation_records, :last_resume_error_at, :datetime

    add_index :continuation_records, %i[run_id status]

    reversible do |dir|
      dir.up do
        remove_check_constraint :continuation_records, name: "continuation_records_status_check"
        add_check_constraint :continuation_records, "status in ('current','consuming','consumed')", name: "continuation_records_status_check"
      end

      dir.down do
        remove_check_constraint :continuation_records, name: "continuation_records_status_check"
        add_check_constraint :continuation_records, "status in ('current','consumed')", name: "continuation_records_status_check"
      end
    end
  end
end
