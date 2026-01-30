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

  def pending!(reason)
    skip("Pending Wave 4 (Pipeline): #{reason}")
  end

  def test_trace_collector_records_stable_stage_order
    pending!("SillyTavern pipeline must emit stable stage names via TraceCollector")

    _instrumenter = TavernKit::Prompt::Instrumenter::TraceCollector.new

    # Contract shape (pseudocode):
    # TavernKit::SillyTavern.build do
    #   instrumenter instrumenter
    #   strict true
    #   character ...
    #   user ...
    #   preset ...
    #   history ...
    #   message "Hello"
    # end
    #
    # assert_equal EXPECTED_STAGE_NAMES, instrumenter.stages.map(&:name)
  end
end
