# frozen_string_literal: true

class ToolResultRecord < ApplicationRecord
  EXECUTING_RECLAIM_AFTER = 15.minutes
  QUEUED_REENQUEUE_AFTER = 15.minutes
  STALE_EXECUTION_NOT_RETRIED_MESSAGE = "Tool execution timed out and was not retried (tool is not marked retryable)."

  validates :run_id, presence: true
  validates :tool_call_id, presence: true
  validates :status, inclusion: { in: %w[queued executing ready cancelled] }

  validate :validate_tool_result_matches_status

  scope :ready, -> { where(status: "ready") }

  def self.reserve!(run_id:, tool_call_id:, executed_name:)
    rid = run_id.to_s
    tcid = tool_call_id.to_s
    now = Time.current

    record =
      create!(
        run_id: rid,
        tool_call_id: tcid,
        executed_name: executed_name.to_s.presence,
        tool_result: nil,
        status: "queued",
        enqueued_at: now,
      )

    [record, true]
  rescue ActiveRecord::RecordNotUnique
    [find_by!(run_id: rid, tool_call_id: tcid), false]
  end

  def self.claim_for_execution!(run_id:, tool_call_id:, job_id:)
    rid = run_id.to_s
    tcid = tool_call_id.to_s
    now = Time.current

    updated =
      where(run_id: rid, tool_call_id: tcid, status: "queued")
        .update_all(
          status: "executing",
          started_at: now,
          locked_by: job_id.to_s,
          updated_at: now,
        )

    updated == 1
  end

  def self.reclaim_stale_executing!(run_id:, tool_call_id:, reclaim_after: EXECUTING_RECLAIM_AFTER)
    rid = run_id.to_s
    tcid = tool_call_id.to_s
    now = Time.current
    reclaim_before = now - reclaim_after

    updated =
      where(run_id: rid, tool_call_id: tcid, status: "executing")
        .where("started_at IS NULL OR started_at < ?", reclaim_before)
        .update_all(
          status: "queued",
          started_at: nil,
          locked_by: nil,
          enqueued_at: now,
          updated_at: now,
        )

    updated == 1
  end

  def self.fail_stale_executing!(run_id:, tool_call_id:, reclaim_after: EXECUTING_RECLAIM_AFTER)
    rid = run_id.to_s
    tcid = tool_call_id.to_s
    now = Time.current
    reclaim_before = now - reclaim_after

    error_result =
      AgentCore::Resources::Tools::ToolResult.error(
        text: STALE_EXECUTION_NOT_RETRIED_MESSAGE,
        metadata: {
          stale_execution: true,
          retryable: false,
          reclaim_after_s: reclaim_after.to_i,
        },
      )

    payload = canonicalize_tool_result_payload(error_result)

    updated =
      where(run_id: rid, tool_call_id: tcid, status: "executing")
        .where("started_at IS NULL OR started_at < ?", reclaim_before)
        .update_all(
          status: "ready",
          tool_result: payload,
          finished_at: now,
          locked_by: nil,
          updated_at: now,
        )

    updated == 1
  end

  def self.reenqueue_stale_queued!(run_id:, tool_call_id:, reenqueue_after: QUEUED_REENQUEUE_AFTER)
    rid = run_id.to_s
    tcid = tool_call_id.to_s
    now = Time.current
    reenqueue_before = now - reenqueue_after

    updated =
      where(run_id: rid, tool_call_id: tcid, status: "queued")
        .where("enqueued_at IS NULL OR enqueued_at < ?", reenqueue_before)
        .update_all(
          enqueued_at: now,
          updated_at: now,
        )

    updated == 1
  end

  def self.complete!(run_id:, tool_call_id:, job_id:, tool_result:)
    rid = run_id.to_s
    tcid = tool_call_id.to_s
    now = Time.current

    result =
      if tool_result.is_a?(AgentCore::Resources::Tools::ToolResult)
        tool_result
      else
        AgentCore::Resources::Tools::ToolResult.from_h(tool_result)
      end

    payload = canonicalize_tool_result_payload(result)

    updated =
      where(run_id: rid, tool_call_id: tcid, status: "executing", locked_by: job_id.to_s)
        .update_all(
          status: "ready",
          tool_result: payload,
          finished_at: now,
          updated_at: now,
        )

    return true if updated == 1

    record = find_by(run_id: rid, tool_call_id: tcid)
    return true if record&.status == "ready" && record.tool_result == payload

    raise ArgumentError, "unable to complete tool result: run_id=#{rid} tool_call_id=#{tcid}"
  end

  def self.upsert_result!(run_id:, tool_call_id:, executed_name: nil, tool_result:)
    rid = run_id.to_s
    tcid = tool_call_id.to_s

    result =
      if tool_result.is_a?(AgentCore::Resources::Tools::ToolResult)
        tool_result
      else
        AgentCore::Resources::Tools::ToolResult.from_h(tool_result)
      end

    payload = canonicalize_tool_result_payload(result)

    record = find_by(run_id: rid, tool_call_id: tcid)
    if record
      raise ArgumentError, "cancelled tool result: run_id=#{rid} tool_call_id=#{tcid}" if record.status == "cancelled"

      return record if record.status == "ready" && record.tool_result == payload

      if record.status != "ready" && record.tool_result.nil?
        record.update!(
          executed_name: record.executed_name.presence || executed_name.to_s.presence,
          status: "ready",
          tool_result: payload,
          finished_at: Time.current,
        )
        return record
      end

      raise ArgumentError, "conflicting tool result: run_id=#{rid} tool_call_id=#{tcid}"
    end

    create!(
      run_id: rid,
      tool_call_id: tcid,
      executed_name: executed_name.to_s.presence,
      tool_result: payload,
      status: "ready",
      finished_at: Time.current,
    )
  rescue ActiveRecord::RecordNotUnique
    record = find_by!(run_id: rid, tool_call_id: tcid)
    raise ArgumentError, "cancelled tool result: run_id=#{rid} tool_call_id=#{tcid}" if record.status == "cancelled"
    return record if record.tool_result == payload

    raise ArgumentError, "conflicting tool result: run_id=#{rid} tool_call_id=#{tcid}"
  end

  def self.cancel_run!(run_id:)
    rid = run_id.to_s
    now = Time.current

    where(run_id: rid, status: %w[queued executing])
      .update_all(
        status: "cancelled",
        locked_by: nil,
        started_at: nil,
        enqueued_at: nil,
        finished_at: now,
        tool_result: nil,
        updated_at: now,
      )
  end

  def self.canonicalize_tool_result_payload(result)
    raw = AgentCore::Utils.deep_stringify_keys(result.to_h)
    JSON.parse(JSON.generate(raw))
  rescue StandardError
    raw
  end
  private_class_method :canonicalize_tool_result_payload

  def validate_tool_result_matches_status
    if status == "ready"
      errors.add(:tool_result, "must be present when status is ready") if tool_result.nil?
    else
      errors.add(:tool_result, "must be nil when status is #{status}") if tool_result.present?
    end
  end
end
