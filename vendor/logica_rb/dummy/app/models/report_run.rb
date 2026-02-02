# frozen_string_literal: true

class ReportRun < ApplicationRecord
  belongs_to :report

  validates :status, presence: true
end
