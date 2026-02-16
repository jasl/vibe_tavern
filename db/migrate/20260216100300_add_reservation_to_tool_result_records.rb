# frozen_string_literal: true

class AddReservationToToolResultRecords < ActiveRecord::Migration[8.2]
  def change
    change_column_null :tool_result_records, :tool_result, true

    add_column :tool_result_records, :enqueued_at, :datetime
    add_column :tool_result_records, :started_at, :datetime
    add_column :tool_result_records, :finished_at, :datetime
    add_column :tool_result_records, :locked_by, :string

    change_column_default :tool_result_records, :status, from: "ready", to: "queued"

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE tool_result_records
             SET status = 'ready'
           WHERE tool_result IS NOT NULL
             AND status <> 'ready'
        SQL

        execute <<~SQL.squish
          UPDATE tool_result_records
             SET finished_at = COALESCE(finished_at, updated_at)
           WHERE status = 'ready'
        SQL

        execute <<~SQL.squish
          UPDATE tool_result_records
             SET status = 'queued'
           WHERE status = 'ready'
             AND tool_result IS NULL
        SQL

        add_check_constraint :tool_result_records, "status in ('queued','executing','ready')", name: "tool_result_records_status_check"
        add_check_constraint :tool_result_records, "(status = 'ready') = (tool_result IS NOT NULL)", name: "tool_result_records_ready_tool_result_check"
      end

      dir.down do
        remove_check_constraint :tool_result_records, name: "tool_result_records_ready_tool_result_check"
        remove_check_constraint :tool_result_records, name: "tool_result_records_status_check"
      end
    end
  end
end
