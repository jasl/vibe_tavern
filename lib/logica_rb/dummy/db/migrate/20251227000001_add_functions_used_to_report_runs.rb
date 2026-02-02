# frozen_string_literal: true

class AddFunctionsUsedToReportRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :report_runs, :functions_used, :json, null: false, default: []
  end
end
