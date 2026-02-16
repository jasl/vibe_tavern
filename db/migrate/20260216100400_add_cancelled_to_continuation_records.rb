# frozen_string_literal: true

class AddCancelledToContinuationRecords < ActiveRecord::Migration[8.2]
  def change
    add_column :continuation_records, :cancelled_at, :datetime

    reversible do |dir|
      dir.up do
        remove_check_constraint :continuation_records, name: "continuation_records_status_check"
        add_check_constraint :continuation_records, "status in ('current','consuming','consumed','cancelled')", name: "continuation_records_status_check"
      end

      dir.down do
        remove_check_constraint :continuation_records, name: "continuation_records_status_check"
        add_check_constraint :continuation_records, "status in ('current','consuming','consumed')", name: "continuation_records_status_check"
      end
    end
  end
end
