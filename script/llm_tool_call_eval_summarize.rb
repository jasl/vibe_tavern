#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"
require "time"

root = Pathname.new(__dir__).join("..").expand_path

raw_report_dir = ARGV.fetch(0, nil).to_s.strip
raw_report_dir = ENV.fetch("OPENROUTER_REPORT_DIR", "").to_s.strip if raw_report_dir.empty?

if raw_report_dir.empty?
  warn "Usage: bundle exec ruby script/llm_tool_call_eval_summarize.rb tmp/llm_tool_call_eval_reports/<timestamp>"
  warn "  or:  OPENROUTER_REPORT_DIR=tmp/llm_tool_call_eval_reports/<timestamp> bundle exec ruby script/llm_tool_call_eval_summarize.rb"
  exit 2
end

report_dir = Pathname.new(raw_report_dir)
report_dir = root.join(report_dir) unless report_dir.absolute?
report_dir = report_dir.expand_path

unless report_dir.directory?
  warn "Report dir does not exist: #{report_dir}"
  exit 2
end

json_paths =
  report_dir
    .children
    .select { |path| path.file? && path.extname == ".json" && !path.basename.to_s.start_with?("summary") }
    .sort

if json_paths.empty?
  warn "No run JSON files found under: #{report_dir}"
  exit 2
end

run_results =
  json_paths.filter_map do |path|
    begin
      data = JSON.parse(path.read)
    rescue JSON::ParserError
      warn "Skipping invalid JSON: #{path}"
      next
    end

    next unless data.is_a?(Hash)

    {
      model: data["model"].to_s,
      model_base: data["model_base"].to_s,
      strategy: data["strategy"].to_s,
      fallback_profile: data["fallback_profile"].to_s,
      sampling_profile: data["sampling_profile"].to_s,
      content_tag_tool_call_fallback: data["content_tag_tool_call_fallback"] == true,
      scenario: data["scenario"].to_s,
      trial: data["trial"].to_i,
      ok: data["ok"] == true,
      elapsed_ms: data["elapsed_ms"].to_i,
      error: data["error"],
      error_hint: data["error_hint"],
      error_status: data["error_status"],
      error_category: data["error_category"],
      report_path: path.relative_path_from(root).to_s,
    }
  end

if run_results.empty?
  warn "No valid run results found under: #{report_dir}"
  exit 2
end

def percentile(sorted, p)
  return 0 if sorted.empty?

  idx = (sorted.length * p).floor
  sorted[[idx, sorted.length - 1].min].to_i
end

reports =
  run_results
    .group_by { |r| [r[:model_base], r[:sampling_profile], r[:strategy], r[:fallback_profile]] }
    .map do |(_model_base, _sampling_profile, _strategy, _fallback_profile), runs|
      ok_count = runs.count { |r| r[:ok] }
      elapsed = runs.map { |r| r[:elapsed_ms].to_i }.sort
      tool_runs = runs.reject { |r| r[:scenario].to_s == "chat_only" }
      tool_ok_count = tool_runs.count { |r| r[:ok] }
      tool_elapsed = tool_runs.map { |r| r[:elapsed_ms].to_i }.sort
      control_runs = runs.select { |r| r[:scenario].to_s == "chat_only" }
      control_ok_count = control_runs.count { |r| r[:ok] }
      control_elapsed = control_runs.map { |r| r[:elapsed_ms].to_i }.sort

      {
        model: runs[0][:model],
        model_base: runs[0][:model_base],
        strategy: runs[0][:strategy],
        fallback_profile: runs[0][:fallback_profile],
        sampling_profile: runs[0][:sampling_profile],
        content_tag_tool_call_fallback: runs[0][:content_tag_tool_call_fallback],
        runs: runs.size,
        ok: ok_count,
        ok_rate: ok_count.fdiv(runs.size),
        ms_p50: percentile(elapsed, 0.50),
        ms_p95: percentile(elapsed, 0.95),
        tool_runs: tool_runs.size,
        tool_ok: tool_ok_count,
        tool_ok_rate: tool_runs.empty? ? nil : tool_ok_count.fdiv(tool_runs.size),
        tool_ms_p50: percentile(tool_elapsed, 0.50),
        tool_ms_p95: percentile(tool_elapsed, 0.95),
        control_runs: control_runs.size,
        control_ok: control_ok_count,
        control_ok_rate: control_runs.empty? ? nil : control_ok_count.fdiv(control_runs.size),
        control_ms_p50: percentile(control_elapsed, 0.50),
        control_ms_p95: percentile(control_elapsed, 0.95),
        scenarios: runs.map { |r| r[:scenario] }.uniq.sort,
        run_results: runs.sort_by { |r| [r[:scenario].to_s, r[:trial].to_i, r[:report_path].to_s] },
        failure_samples: runs.reject { |r| r[:ok] }.first(3),
      }
    end
    .sort_by { |r| [r[:model_base].to_s, r[:sampling_profile].to_s, r[:strategy].to_s, r[:fallback_profile].to_s] }

all_scenarios = run_results.map { |r| r[:scenario] }.uniq.sort

summary_by_scenario =
  run_results.each_with_object({}) do |run, out|
    sid = run[:scenario].to_s
    out[sid] ||= { "runs" => 0, "ok" => 0, "errors" => Hash.new(0) }
    out[sid]["runs"] += 1
    out[sid]["ok"] += 1 if run[:ok] == true

    next if run[:ok] == true

    cat = run[:error_category].to_s
    cat = "unknown" if cat.empty?
    out[sid]["errors"][cat] += 1
  end
summary_by_scenario.each_value { |v| v["errors"] = v["errors"].to_h }

summary_by_scenario_and_strategy =
  run_results.each_with_object({}) do |run, out|
    strategy = run[:strategy].to_s
    strategy = "(unknown)" if strategy.empty?
    sid = run[:scenario].to_s

    out[strategy] ||= {}
    out[strategy][sid] ||= { "runs" => 0, "ok" => 0, "errors" => Hash.new(0) }
    out[strategy][sid]["runs"] += 1
    out[strategy][sid]["ok"] += 1 if run[:ok] == true

    next if run[:ok] == true

    cat = run[:error_category].to_s
    cat = "unknown" if cat.empty?
    out[strategy][sid]["errors"][cat] += 1
  end

summary_by_scenario_and_strategy.each_value do |by_scenario|
  by_scenario.each_value { |v| v["errors"] = v["errors"].to_h }
end

summary = {
  ts: Time.now.utc.iso8601,
  source: "llm_tool_call_eval_summarize",
  output_dir: report_dir.to_s,
  scenarios: all_scenarios,
  model_profiles: reports.size,
  runs: run_results.size,
  ok: run_results.count { |r| r[:ok] },
  fail: run_results.count { |r| !r[:ok] },
  tool_runs: run_results.count { |r| r[:scenario].to_s != "chat_only" },
  tool_ok: run_results.count { |r| r[:scenario].to_s != "chat_only" && r[:ok] },
  control_runs: run_results.count { |r| r[:scenario].to_s == "chat_only" },
  control_ok: run_results.count { |r| r[:scenario].to_s == "chat_only" && r[:ok] },
  models: reports,
}

File.write(report_dir.join("summary.json"), JSON.pretty_generate(summary))
File.write(report_dir.join("summary_by_scenario.json"), JSON.pretty_generate(summary_by_scenario))
File.write(report_dir.join("summary_by_scenario_and_strategy.json"), JSON.pretty_generate(summary_by_scenario_and_strategy))

puts "LLM Tool Call Eval (summarize only)"
puts "ts: #{summary[:ts]}"
puts "runs: #{summary[:runs]} (ok=#{summary[:ok]}, fail=#{summary[:fail]})"
puts "model_profiles: #{summary[:model_profiles]}"
puts "scenarios: #{all_scenarios.join(",")}"
puts "full report: #{report_dir.relative_path_from(root)}"
