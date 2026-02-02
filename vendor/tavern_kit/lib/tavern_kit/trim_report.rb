# frozen_string_literal: true

module TavernKit
  # Per-block eviction record used by both Lore and Trimmer budgeting.
  EvictionRecord = Data.define(
    :block_id,          # String - Prompt::Block#id
    :slot,              # Symbol, nil - Prompt::Block#slot
    :token_count,       # Integer
    :reason,            # Symbol - :budget_exceeded, :group_overflow, :priority_cutoff, ...
    :budget_group,      # Symbol - Prompt::Block#token_budget_group
    :priority,          # Integer, nil - Prompt::Block#priority (for :priority strategy)
    :source             # Hash, nil - Prompt::Block#metadata[:source] (provenance)
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
    :kept,              # Array<Prompt::Block>
    :evicted,           # Array<Prompt::Block>
    :report             # TrimReport
  )
end
