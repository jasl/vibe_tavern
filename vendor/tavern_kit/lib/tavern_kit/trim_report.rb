# frozen_string_literal: true

module TavernKit
  # Per-block eviction record used by both Lore and Trimmer budgeting.
  EvictionRecord = Data.define(
    :block_id,          # String - PromptBuilder::Block#id
    :slot,              # Symbol, nil - PromptBuilder::Block#slot
    :token_count,       # Integer
    :reason,            # Symbol - :budget_exceeded, :group_overflow, :priority_cutoff, ...
    :budget_group,      # Symbol - PromptBuilder::Block#token_budget_group
    :priority,          # Integer, nil - PromptBuilder::Block#priority (for :priority strategy)
    :source             # Hash, nil - PromptBuilder::Block#metadata[:source] (provenance)
  )

  # Detailed budgeting report for debugging and observability.
  TrimReport = Data.define(
    :strategy,          # Symbol - :group_order or :priority
    :budget_tokens,     # Integer - max tokens allowed
    :initial_tokens,    # Integer - tokens before trimming
    :final_tokens,      # Integer - tokens after trimming
    :eviction_count,    # Integer - number of blocks evicted
    :evictions          # Array<EvictionRecord>
  ) do
    def tokens_saved = initial_tokens - final_tokens
    def over_budget? = initial_tokens > budget_tokens
  end

  # Immutable result of a trim operation.
  TrimResult = Data.define(
    :kept,              # Array<PromptBuilder::Block>
    :evicted,           # Array<PromptBuilder::Block>
    :report             # TrimReport
  )
end
