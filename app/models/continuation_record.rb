# frozen_string_literal: true

class ContinuationRecord < ApplicationRecord
  class BusyContinuationError < StandardError; end
  class StaleContinuationError < StandardError; end

  belongs_to :llm_model

  scope :current, -> { where(status: "current") }

  validates :run_id, presence: true
  validates :continuation_id, presence: true
  validates :tooling_key, presence: true
  validates :status, inclusion: { in: %w[current consuming consumed cancelled] }
  validates :payload, presence: true

  def self.current_for_run!(run_id)
    current.find_by!(run_id: run_id.to_s)
  end

  def self.claim_for_resume!(run_id:, continuation_id:, reclaim_after: 5.minutes)
    rid = run_id.to_s
    cid = continuation_id.to_s
    now = Time.current
    token = SecureRandom.uuid

    updated =
      where(run_id: rid, continuation_id: cid, status: "current")
        .update_all(
          status: "consuming",
          consuming_at: now,
          resume_lock_token: token,
          resume_attempts: Arel.sql("resume_attempts + 1"),
          updated_at: now,
        )

    return token if updated == 1

    reclaim_before = now - reclaim_after

    updated =
      where(run_id: rid, continuation_id: cid, status: "consuming")
        .where("consuming_at IS NULL OR consuming_at < ?", reclaim_before)
        .update_all(
          consuming_at: now,
          resume_lock_token: token,
          resume_attempts: Arel.sql("resume_attempts + 1"),
          updated_at: now,
        )

    return token if updated == 1

    record = find_by(run_id: rid, continuation_id: cid)
    raise StaleContinuationError, "stale continuation: run_id=#{rid} continuation_id=#{cid}" if record.nil? || record.status == "consumed"
    raise StaleContinuationError, "cancelled continuation: run_id=#{rid} continuation_id=#{cid}" if record.status == "cancelled"

    raise BusyContinuationError, "continuation is busy: run_id=#{rid} continuation_id=#{cid}"
  end

  def self.mark_consumed!(run_id:, continuation_id:, lock_token:)
    rid = run_id.to_s
    cid = continuation_id.to_s
    token = lock_token.to_s
    now = Time.current

    updated =
      where(run_id: rid, continuation_id: cid, status: "consuming", resume_lock_token: token)
        .update_all(
          status: "consumed",
          consumed_at: now,
          consuming_at: nil,
          resume_lock_token: nil,
          updated_at: now,
        )

    return true if updated == 1

    raise StaleContinuationError, "unable to mark consumed: run_id=#{rid} continuation_id=#{cid}"
  end

  def self.release_after_failure!(run_id:, continuation_id:, lock_token:, error:)
    rid = run_id.to_s
    cid = continuation_id.to_s
    token = lock_token.to_s
    now = Time.current

    error_class = error.class.name.to_s
    error_message = error.message.to_s
    error_message = error_message.byteslice(0, 10_000) if error_message.bytesize > 10_000

    updated =
      where(run_id: rid, continuation_id: cid, status: "consuming", resume_lock_token: token)
        .update_all(
          status: "current",
          consuming_at: nil,
          resume_lock_token: nil,
          last_resume_error_class: error_class.presence,
          last_resume_error_message: error_message.presence,
          last_resume_error_at: now,
          updated_at: now,
        )

    return true if updated == 1

    raise StaleContinuationError, "unable to release continuation: run_id=#{rid} continuation_id=#{cid}"
  end

  def self.cancel_run!(run_id:, reason: nil)
    _reason = reason
    rid = run_id.to_s
    now = Time.current

    where(run_id: rid, status: %w[current consuming])
      .update_all(
        status: "cancelled",
        cancelled_at: now,
        consuming_at: nil,
        resume_lock_token: nil,
        updated_at: now,
      )
  end
end
