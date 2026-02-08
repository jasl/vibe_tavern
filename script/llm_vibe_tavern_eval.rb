#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "rbconfig"

eval_preset = ENV.fetch("OPENROUTER_EVAL_PRESET", "").to_s.strip
eval_preset = "full" if eval_preset.empty? && ENV.fetch("OPENROUTER_FULL", "0") == "1"
eval_preset = "full" if eval_preset.empty?

api_key = ENV.fetch("OPENROUTER_API_KEY", "").to_s.strip
if api_key.empty?
  warn "Missing OPENROUTER_API_KEY."
  exit 2
end

def run_child(label, env, *cmd)
  report_dir = nil

  Open3.popen2e(env, *cmd) do |_stdin, out, wait_thr|
    out.each_line do |line|
      puts line
      if (m = line.match(/full report: (.+)$/))
        report_dir = m[1].to_s.strip
      end
    end

    status = wait_thr.value
    unless status.success?
      warn "#{label} failed with exit=#{status.exitstatus || 1}"
      exit(status.exitstatus || 1)
    end
  end

  report_dir
end

ruby = RbConfig.ruby
script_dir = File.expand_path(__dir__)
tool_call_script = File.join(script_dir, "llm_tool_call_eval.rb")
directives_script = File.join(script_dir, "llm_directives_eval.rb")

child_env = ENV.to_h
child_env["OPENROUTER_EVAL_PRESET"] = eval_preset

puts "VibeTavern Eval"
puts "preset: #{eval_preset}"
puts "tool calling: #{tool_call_script}"
puts "directives: #{directives_script}"
puts

tool_report =
  run_child(
    "tool calling",
    child_env,
    ruby,
    tool_call_script,
  )

directives_report =
  run_child(
    "directives",
    child_env,
    ruby,
    directives_script,
  )

puts
puts "Done."
puts "tool calling report: #{tool_report || "(unknown)"}"
puts "directives report: #{directives_report || "(unknown)"}"
