# frozen_string_literal: true

require "test_helper"

class VibeTavernTokenEstimationThreadSafetyTest < ActiveSupport::TestCase
  test "estimator cache is thread-safe" do
    mod = TavernKit::VibeTavern::TokenEstimation
    mod.instance_variable_set(:@estimators, {})

    start_barrier = Queue.new
    results = Queue.new

    threads =
      Array.new(20) do
        Thread.new do
          start_barrier.pop
          results << mod.estimator(root: Rails.root).object_id
        end
      end

    threads.size.times { start_barrier << true }
    threads.each(&:value)

    object_ids = threads.size.times.map { results.pop }
    assert_equal 1, object_ids.uniq.size
  end
end
