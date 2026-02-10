#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"

ENV["RAILS_ENV"] ||= "development"

# Boot Bundler/Bootsnap without loading full Rails.
require_relative "../config/boot"

require "tavern_kit"

# App-owned pipeline (not loaded by the gem).
require_relative "../lib/tavern_kit/vibe_tavern/pipeline"

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

  CheapTokenEstimator =
    Class.new do
      def estimate(text, model_hint: nil)
        _ = model_hint
        ((text.to_s.bytesize / 4.0).ceil).clamp(1, 1_000_000)
      end

      def describe(model_hint: nil)
        _ = model_hint
        { backend: "cheap", encoding: "bytes/4" }
      end
    end

  def cheap_estimator
    @cheap_estimator ||= CheapTokenEstimator.new
  end

  def build_history(length, kind:)
    messages =
      Array.new(length) do |i|
        role = i.even? ? :user : :assistant
        TavernKit::PromptBuilder::Message.new(role: role, content: "hello #{i}")
      end

    case kind
    when "in_memory"
      TavernKit::ChatHistory::InMemory.new(messages)
    when "array_messages"
      messages
    when "array_hashes"
      messages.map { |m| { role: m.role, content: m.content } }
    else
      raise ArgumentError, "unknown HISTORY_KIND: #{kind.inspect}"
    end
  end

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

    cases = env_list("CASES", "vibe_tavern,silly_tavern")
    mode = env_choice("MODE", "build", allowed: %w[build to_messages both])
    format = env_choice("FORMAT", "table", allowed: %w[table jsonl])
    history_kind = env_choice("HISTORY_KIND", "in_memory", allowed: %w[in_memory array_messages array_hashes])

    gc_mode = env_choice("GC_MODE", "enable", allowed: %w[enable disable])
    gc_was_enabled = nil
    gc_was_enabled = GC.disable if gc_mode == "disable"

    history = build_history(history_len, kind: history_kind)

    character = TavernKit::Character.create(name: "Alice", description: "A test character.")
    user = TavernKit::User.new(name: "Bob", persona: "A test persona.")

    vibe_configs_on = {
      language_policy: {
        enabled: true,
        target_lang: "zh-CN",
        special_tags: ["lang"],
      },
    }

    results = []

    if cases.include?("vibe_tavern")
      pipeline = TavernKit::VibeTavern::Pipeline
      base_inputs = {
        pipeline: pipeline,
        character: character,
        user: user,
        history: history,
        message: "Hello, world.",
        token_estimator: cheap_estimator,
      }

      if mode == "build" || mode == "both"
        results << run_case("vibe_tavern:build", warmup: warmup, iterations: iterations) do
          measure(warmup: warmup, iterations: iterations) do
            TavernKit::PromptBuilder.build(**base_inputs)
          end
        end

        results << run_case("vibe_tavern:build+language_policy", warmup: warmup, iterations: iterations) do
          measure(warmup: warmup, iterations: iterations) do
            TavernKit::PromptBuilder.build(**base_inputs, configs: vibe_configs_on)
          end
        end
      end

      if mode == "to_messages" || mode == "both"
        results << run_case("vibe_tavern:to_messages", warmup: warmup, iterations: iterations) do
          measure(warmup: warmup, iterations: iterations) do
            TavernKit::PromptBuilder.to_messages(dialect: :openai, **base_inputs)
          end
        end
      end
    end

    if cases.include?("silly_tavern")
      pipeline = TavernKit::SillyTavern::Pipeline
      base_inputs = {
        pipeline: pipeline,
        character: character,
        user: user,
        history: history,
        message: "Hello, world.",
        token_estimator: cheap_estimator,
      }

      if mode == "build" || mode == "both"
        results << run_case("silly_tavern:build", warmup: warmup, iterations: iterations) do
          measure(warmup: warmup, iterations: iterations) do
            TavernKit::PromptBuilder.build(**base_inputs)
          end
        end
      end

      if mode == "to_messages" || mode == "both"
        results << run_case("silly_tavern:to_messages", warmup: warmup, iterations: iterations) do
          measure(warmup: warmup, iterations: iterations) do
            TavernKit::PromptBuilder.to_messages(dialect: :openai, **base_inputs)
          end
        end
      end
    end

    if cases.include?("risu_ai")
      pipeline = TavernKit::RisuAI::Pipeline
      base_inputs = {
        pipeline: pipeline,
        character: character,
        user: user,
        history: history,
        message: "Hello, world.",
        token_estimator: cheap_estimator,
      }

      if mode == "build" || mode == "both"
        results << run_case("risu_ai:build", warmup: warmup, iterations: iterations) do
          measure(warmup: warmup, iterations: iterations) do
            TavernKit::PromptBuilder.build(**base_inputs)
          end
        end
      end

      if mode == "to_messages" || mode == "both"
        results << run_case("risu_ai:to_messages", warmup: warmup, iterations: iterations) do
          measure(warmup: warmup, iterations: iterations) do
            TavernKit::PromptBuilder.to_messages(dialect: :openai, **base_inputs)
          end
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
      puts "- This measures only local prompt-building (no LLM/network)."
      puts "- HISTORY_KIND=in_memory avoids per-run history normalization overhead."
      puts "- GC_MODE=disable can reduce noise but may increase memory usage."
    end
  ensure
    GC.enable if gc_was_enabled == true
  end
end

PromptBuilderBenchmark.main
