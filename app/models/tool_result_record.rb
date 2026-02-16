# frozen_string_literal: true

class ToolResultRecord < ApplicationRecord
  validates :run_id, presence: true
  validates :tool_call_id, presence: true
  validates :tool_result, presence: true
  validates :status, presence: true

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
      return record if record.tool_result == payload

      raise ArgumentError, "conflicting tool result: run_id=#{rid} tool_call_id=#{tcid}"
    end

    create!(
      run_id: rid,
      tool_call_id: tcid,
      executed_name: executed_name.to_s.presence,
      tool_result: payload,
      status: "ready",
    )
  rescue ActiveRecord::RecordNotUnique
    record = find_by!(run_id: rid, tool_call_id: tcid)
    return record if record.tool_result == payload

    raise ArgumentError, "conflicting tool result: run_id=#{rid} tool_call_id=#{tcid}"
  end

  def self.canonicalize_tool_result_payload(result)
    raw = AgentCore::Utils.deep_stringify_keys(result.to_h)
    JSON.parse(JSON.generate(raw))
  rescue StandardError
    raw
  end
  private_class_method :canonicalize_tool_result_payload
end
