# frozen_string_literal: true

class ContinuationRecord < ApplicationRecord
  class StaleContinuationError < StandardError; end

  belongs_to :llm_model

  scope :current, -> { where(status: "current") }

  validates :run_id, presence: true
  validates :continuation_id, presence: true
  validates :tooling_key, presence: true
  validates :status, inclusion: { in: %w[current consumed] }
  validates :payload, presence: true

  def self.current_for_run!(run_id)
    current.find_by!(run_id: run_id.to_s)
  end

  def self.consume!(run_id:, continuation_id:)
    rid = run_id.to_s
    cid = continuation_id.to_s
    now = Time.current

    updated =
      where(run_id: rid, continuation_id: cid, status: "current")
        .update_all(status: "consumed", consumed_at: now, updated_at: now)

    return true if updated == 1

    raise StaleContinuationError, "stale continuation: run_id=#{rid} continuation_id=#{cid}"
  end
end
