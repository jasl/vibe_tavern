# frozen_string_literal: true

require "test_helper"

class Wave4PipelineTraceContractTest < Minitest::Test
  EXPECTED_STAGE_NAMES = %i[
    hooks
    lore
    entries
    pinned_groups
    injection
    compilation
    macro_expansion
    plan_assembly
    trimming
  ].freeze

  def test_trace_collector_records_stable_stage_order
    instrumenter = TavernKit::Prompt::Instrumenter::TraceCollector.new

    _plan = TavernKit::SillyTavern.build do
      instrumenter instrumenter
      strict true

      character TavernKit::Character.create(name: "Alice")
      user TavernKit::User.new(name: "You")
      message "Hello"
    end

    assert_equal EXPECTED_STAGE_NAMES, instrumenter.stages.map(&:name)
  end
end
