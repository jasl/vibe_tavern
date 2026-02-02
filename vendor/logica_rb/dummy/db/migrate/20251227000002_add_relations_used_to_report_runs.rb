# frozen_string_literal: true

class AddRelationsUsedToReportRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :report_runs, :relations_used, :json, null: false, default: []
  end
end
