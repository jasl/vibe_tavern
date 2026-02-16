# frozen_string_literal: true

class AddCancelledToToolResultRecords < ActiveRecord::Migration[8.2]
  def change
    reversible do |dir|
      dir.up do
        remove_check_constraint :tool_result_records, name: "tool_result_records_status_check"
        add_check_constraint :tool_result_records, "status in ('queued','executing','ready','cancelled')", name: "tool_result_records_status_check"
      end

      dir.down do
        remove_check_constraint :tool_result_records, name: "tool_result_records_status_check"
        add_check_constraint :tool_result_records, "status in ('queued','executing','ready')", name: "tool_result_records_status_check"
      end
    end
  end
end
