#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"

# Boot Bundler/Bootsnap without loading full Rails.
require_relative "../../config/boot"

require "agent_core"

require_relative "../../lib/agent_core/contrib/openai_history"

module PromptBuilderBenchmark
  module_function

  def env_int(name, default)
    Integer(ENV.fetch(name, default).to_s)
  rescue ArgumentError, TypeError
    default
  end

  def env_list(name, default)
    ENV.fetch(name, default).to_s.split(",").map(&:strip).reject(&:empty?)
  end

  def env_choice(name, default, allowed:)
    value = ENV.fetch(name, default).to_s.strip.downcase
    return value if allowed.include?(value)

    default
  end

  def build_history(length, kind:)
    messages =
      Array.new(length) do |i|
        role = i.even? ? :user : :assistant
        AgentCore::Message.new(role: role, content: "hello #{i}")
      end

    case kind
    when "array_messages"
      messages
    when "array_hashes_symbol_keys"
      messages.map { |m| { role: m.role, content: m.content } }
    when "array_hashes_string_keys"
      messages.map { |m| { "role" => m.role.to_s, "content" => m.content } }
    else
      raise ArgumentError, "unknown HISTORY_KIND: #{kind.inspect}"
    end
  end

  DEFAULT_TOOLS = [
    {
      "type" => "function",
      "function" => {
        "name" => "state_get",
        "description" => "Read workspace state.",
        "parameters" => {
          "type" => "object",
          "additionalProperties" => false,
          "properties" => {
            "workspace_id" => { "type" => "string" },
          },
          "required" => [],
        },
      },
    },
    {
      "type" => "function",
      "function" => {
        "name" => "state_patch",
        "description" => "Apply patch operations to draft state.",
        "parameters" => {
          "type" => "object",
          "additionalProperties" => false,
          "properties" => {
            "request_id" => { "type" => "string" },
            "ops" => { "type" => "array" },
          },
          "required" => ["request_id", "ops"],
        },
      },
    },
  ].freeze

  DEFAULT_OPTIONS = {
    model: "openai/gpt-5.2-chat",
    temperature: 0.7,
    max_tokens: 256,
  }.freeze

  def measure(warmup:, iterations:)
    warmup.times { yield }

    GC.start(full_mark: true, immediate_sweep: true)

    start_alloc = GC.stat(:total_allocated_objects)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    iterations.times { yield }

    elapsed_s = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    allocated = GC.stat(:total_allocated_objects) - start_alloc

    {
      iterations: iterations,
      elapsed_ms: (elapsed_s * 1000.0).round(3),
      ms_per_iter: (elapsed_s * 1000.0 / iterations).round(6),
      allocated_objects: allocated,
      allocated_objects_per_iter: (allocated.to_f / iterations).round(3),
    }
  end

  def run_case(id, warmup:, iterations:)
    result = yield
    result.merge(id: id)
  end

  def print_table(results)
    puts "PromptBuilder Benchmark"
    puts "ruby: #{RUBY_DESCRIPTION}"
    puts "time: #{Time.now.utc.iso8601}"
    puts

    header = [
      "case",
      "iters",
      "total_ms",
      "ms/iter",
      "alloc_objs",
      "alloc/iter",
    ]
    puts header.join("\t")

    results.each do |r|
      puts(
        [
          r.fetch(:id),
          r.fetch(:iterations),
          r.fetch(:elapsed_ms),
          r.fetch(:ms_per_iter),
          r.fetch(:allocated_objects),
          r.fetch(:allocated_objects_per_iter),
        ].join("\t"),
      )
    end
  end

  def main
    warmup = env_int("WARMUP", 50)
    iterations = env_int("ITER", 300)
    history_len = env_int("HISTORY", 8)

    cases = env_list("CASES", "coerce_messages,built_prompt,built_prompt_with_coerce,estimate_tokens")
    format = env_choice("FORMAT", "table", allowed: %w[table jsonl])
    history_kind =
      env_choice(
        "HISTORY_KIND",
        "array_hashes_string_keys",
        allowed: %w[array_messages array_hashes_symbol_keys array_hashes_string_keys],
      )
    tools_mode = env_choice("TOOLS", "on", allowed: %w[on off])
    tools = tools_mode == "on" ? DEFAULT_TOOLS : []
    system_prompt = ENV.fetch("SYSTEM", "You are a helpful assistant.").to_s
    options = DEFAULT_OPTIONS
    token_counter = AgentCore::Resources::TokenCounter::Heuristic.new

    gc_mode = env_choice("GC_MODE", "enable", allowed: %w[enable disable])
    gc_was_enabled = nil
    gc_was_enabled = GC.disable if gc_mode == "disable"

    history_input = build_history(history_len, kind: history_kind)

    results = []

    if cases.include?("coerce_messages")
      results << run_case("#{history_kind}:coerce_messages", warmup: warmup, iterations: iterations) do
        measure(warmup: warmup, iterations: iterations) do
          AgentCore::Contrib::OpenAIHistory.coerce_messages(history_input)
        end
      end
    end

    base_messages =
      if history_input.is_a?(Array) && history_input.all? { |m| m.is_a?(AgentCore::Message) }
        history_input
      else
        AgentCore::Contrib::OpenAIHistory.coerce_messages(history_input)
      end

    if cases.include?("built_prompt")
      results << run_case("#{history_kind}:built_prompt", warmup: warmup, iterations: iterations) do
        measure(warmup: warmup, iterations: iterations) do
          AgentCore::PromptBuilder::BuiltPrompt.new(
            system_prompt: system_prompt,
            messages: base_messages.dup,
            tools: tools,
            options: options,
          )
        end
      end
    end

    if cases.include?("built_prompt_with_coerce")
      results << run_case("#{history_kind}:built_prompt_with_coerce", warmup: warmup, iterations: iterations) do
        measure(warmup: warmup, iterations: iterations) do
          messages = AgentCore::Contrib::OpenAIHistory.coerce_messages(history_input)
          AgentCore::PromptBuilder::BuiltPrompt.new(
            system_prompt: system_prompt,
            messages: messages,
            tools: tools,
            options: options,
          )
        end
      end
    end

    if cases.include?("estimate_tokens")
      results << run_case("#{history_kind}:estimate_tokens", warmup: warmup, iterations: iterations) do
        measure(warmup: warmup, iterations: iterations) do
          messages = AgentCore::Contrib::OpenAIHistory.coerce_messages(history_input)
          prompt =
            AgentCore::PromptBuilder::BuiltPrompt.new(
              system_prompt: system_prompt,
              messages: messages,
              tools: tools,
              options: options,
            )
          prompt.estimate_tokens(token_counter: token_counter)
        end
      end
    end

    case format
    when "jsonl"
      results.each { |r| puts JSON.generate(r) }
    else
      print_table(results)
      puts
      puts "Notes:"
      puts "- This measures only local prompt assembly (no LLM/network)."
      puts "- CASES controls which steps are included in the measurement."
      puts "- TOOLS=off removes tool-schema serialization overhead from estimate_tokens."
      puts "- GC_MODE=disable can reduce noise but may increase memory usage."
    end
  ensure
    GC.enable if gc_was_enabled == true
  end
end

PromptBuilderBenchmark.main
