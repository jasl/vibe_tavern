# frozen_string_literal: true

require "test_helper"

class PipelineTraceContractTest < Minitest::Test
  # Contract reference:
  # - docs/pipeline-observability.md (TraceCollector semantics)
  EXPECTED_STEP_NAMES = %i[
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

  def test_trace_collector_records_stable_step_order
    instrumenter = TavernKit::PromptBuilder::Instrumenter::TraceCollector.new

    _plan = TavernKit::SillyTavern.build do
      instrumenter instrumenter
      strict true

      character TavernKit::Character.create(name: "Alice")
      user TavernKit::User.new(name: "You")
      message "Hello"
    end

    assert_equal EXPECTED_STEP_NAMES, instrumenter.steps.map(&:name)
  end
end
