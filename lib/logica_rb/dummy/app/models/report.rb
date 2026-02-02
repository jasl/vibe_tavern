# frozen_string_literal: true

class Report < ApplicationRecord
  enum :mode, { file: 0, source: 1 }, prefix: true

  validates :name, presence: true
  validates :predicate, presence: true
  validates :engine, inclusion: { in: %w[auto sqlite psql], allow_blank: false }
  validates :trusted, inclusion: { in: [true, false] }
  validates :allow_imports, inclusion: { in: [true, false] }

  validate :file_source_xor

  private

  def file_source_xor
    if mode_file?
      errors.add(:file, "must be present for file-mode reports") if file.blank?
      errors.add(:source, "must be blank for file-mode reports") if source.present?
    elsif mode_source?
      errors.add(:source, "must be present for source-mode reports") if source.blank?
      errors.add(:file, "must be blank for source-mode reports") if file.present?
    else
      errors.add(:mode, "must be file or source")
    end
  end
end
