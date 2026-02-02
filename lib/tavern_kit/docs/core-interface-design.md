# TavernKit Core Interface Design

Date: 2026-01-29

## Purpose

This document defines the Core interface protocols that both SillyTavern and
RisuAI platform layers implement. The design ensures Core remains platform-
agnostic while providing sufficient flexibility for each platform's unique
requirements.

## Fundamental Insight

The difference between ST and RisuAI is not *what* they do (both build LLM
prompts from character + history + lore + macros), but *where* they store
configuration:

- **ST stores configuration in structured fields.** Entry activation is
  controlled by explicit boolean fields (`matchPersonaDescription: true`),
  enum fields (`selectiveLogic: AND_ALL`), and separate objects
  (`characterFilter`, `triggers`).
- **RisuAI stores configuration inline.** Entry activation is controlled by
  decorators embedded in the content string (`@activate_only_after 5`,
  `@probability 80`). Macro behavior is controlled by block syntax
  (`#when::keep::`, `#each::keep::`).

**Consequence:** Core interfaces define **behavioral contracts** (what goes in,
what comes out), not unified configuration surfaces. Each platform layer handles
its own configuration parsing.

---

## Interface Gap Analysis

| Subsystem | Risk | Required Change |
|-----------|------|-----------------|
| Macro/CBS Engine | **High** | `#expand(text, vars)` too narrow; needs `environment:` parameter object |
| Lore Engine | **Medium-High** | `#scan(text, books:, budget:)` too narrow; needs `ScanInput` parameter object |
| VariablesStore | **Medium** | Missing `temp`/`function_arg` scopes for RisuAI |
| Prompt::Block | **Low** | Implemented in Core: flexible role/points/groups + `removable` flag |
| Prompt::Message | **Low** | Implemented in Core: `attachments`/`metadata` passthrough fields |
| Trimmer | **Low** | Needs pluggable strategy (`:group_order` vs `:priority`) |
| Pipeline/Middleware | **None** | Fully platform-agnostic; no changes needed |
| TokenEstimator | **Low** | Pluggable adapter interface; optional `model_hint:` |
| Character/Card | **None** | `extensions` hash is the forward-compat surface; unknown keys outside extensions may be dropped |

---

## Hash Key Type Convention

TavernKit uses a consistent Hash key type policy to avoid `hash["a"] || hash[:a]`
patterns and unnecessary conversions.

### The Rule

| Context | Key Type | Rationale |
|---------|----------|-----------|
| **Internal domain objects** | **Symbol** | Ruby idiomatic, fast hash lookup |
| **JSON I/O boundary** | **String** (via JSON library) | JSON.parse returns strings; JSON.generate handles symbols |
| **`extensions` Hash** | **String** | Passthrough for external/unknown data |

### Detailed Guidelines

#### Internal Objects (Symbol Keys)

All internal value objects use Symbol keys:

```ruby
# Block#to_h, Message#to_h, Entry#to_h, etc.
{ role: :system, content: "Hello", name: nil }

# Context#metadata
ctx[:my_key] = value
ctx.fetch(:my_key, default)

# Lore::ScanInput options
ScanInput.new(messages: msgs, books: books, budget: 2000)

# TrimReport, Trace, etc.
{ strategy: :group_order, budget_tokens: 4000 }
```

#### JSON Import Boundary (Parse Owned Fields; Keep `extensions` Raw)

When parsing external JSON (presets, cards, etc.), keep the raw payload
**String-keyed** and map owned fields into internal value objects.

Do **not** blanket-symbolize the entire payload, because it would also convert
`extensions` keys to Symbols (breaking the passthrough contract).

```ruby
# In CharacterCard.load, Preset.from_st_json, etc.
# NOTE: JSON parsing happens in the application layer (or TavernKit::Ingest).
def self.load_hash(raw)
  raise ArgumentError, "expected Hash" unless raw.is_a?(Hash)

  raw = Utils.deep_stringify_keys(raw)  # Keep string keys like JSON.parse output
  parse_internal(raw)                  # Parse owned fields explicitly
end

def self.parse_internal(raw)
  data = raw.fetch("data")        # still String keys
  extensions = data["extensions"]
  extensions = {} unless extensions.is_a?(Hash)

  Character::Data.new(
    name: data.fetch("name").to_s,
    # ...
    extensions: extensions,       # Keep String keys
  )
end
```

#### JSON Export (Let JSON Library Handle It)

When exporting to JSON, **do not manually stringify keys**. Ruby's JSON library
handles Symbol -> String conversion automatically:

```ruby
# Internal hash with symbol keys
data = { role: :system, content: "Hello" }

# JSON.generate handles the conversion
JSON.generate(data)  # => '{"role":"system","content":"Hello"}'
```

#### The `extensions` Exception

The `extensions` Hash (in Character, Lore::Entry, etc.) uses **String keys**
because:

1. It stores arbitrary third-party data that TavernKit doesn't interpret
2. Preserves exact key names from external sources
3. Round-trips correctly without normalization

```ruby
# Character extensions (String keys)
character.data.extensions["chub/alt_expressions"]  # ✓ correct
character.data.extensions[:chub_alt_expressions]   # ✗ wrong

# Lore::Entry extensions (String keys)
entry.extensions["sillyTavern/sticky"]             # ✓ correct
```

### What to Avoid

```ruby
# ✗ WRONG: Defensive multi-key access in-line
value = hash["key"] || hash[:key]

# ✗ WRONG: Blanket symbolization of external payloads
# (also converts `extensions` keys, breaking passthrough)
raw = JSON.parse(input)
symbolized = Utils.deep_symbolize_keys(raw)

# ✗ WRONG: Manual stringify before JSON
def to_json
  JSON.generate(Utils.deep_stringify_keys(to_h))  # Unnecessary
end
```

### Hash Normalization Pattern (Current)

TavernKit intentionally accepts **external** Hash inputs that may be:
- String-keyed (typical `JSON.parse`)
- Symbol-keyed (Ruby ergonomics)
- camelCase or snake_case (platform JSON vs Ruby style)

To keep the implementation consistent (and avoid repeating `h[:x] || h["x"] || h[:xY]...` patterns),
we normalize **once at the boundary** and then only use one canonical shape internally.

Preferred options:
- **JSON-like payloads (cards/presets/books):** `Utils.deep_stringify_keys(raw)` and then parse owned fields explicitly.
  - Keep `extensions` as a String-keyed Hash (passthrough contract).
- **Mixed-key feature flags / config hashes:** `Utils::HashAccessor.wrap(hash)` to read alternative spellings
  without sprinkling manual fallbacks.
- **Runtime/app-state contract:** `Runtime::Base.normalize(raw)` to canonicalize keys into
  snake_case Symbols (because runtime keys are TavernKit-owned).

---

## Core Interface Protocols

### 1. Macro::Engine::Base

Accepts an Environment protocol object instead of bare `vars` Hash. The two
engines have zero shared parsing logic (ST uses formal grammar; RisuAI uses
character-by-character scanner), so Core only defines the contract boundary,
not parsing infrastructure.

```ruby
module TavernKit::Macro
  module Engine
    class Base
      # @param text [String] template text with macro placeholders
      # @param environment [Macro::Environment::Base] execution environment
      # @return [String] expanded text
      def expand(text, environment:) = raise NotImplementedError
    end
  end

  module Environment
    class Base
      # Minimal shared protocol -- both platforms implement
      def character_name = raise NotImplementedError
      def user_name = raise NotImplementedError
      def get_var(name, scope: :local) = raise NotImplementedError
      def set_var(name, value, scope: :local) = raise NotImplementedError
      def has_var?(name, scope: :local) = raise NotImplementedError
      # ST extends: instruct_config, clock, rng, content_hash, extensions...
      # RisuAI extends: chat_index, toggles, metadata, modules, assets...
    end
  end

  module Registry
    class Base
      # metadata is opaque to Core; platforms define their own keys
      # ST uses: type, arity, strictArgs, delayArgResolution
      # RisuAI uses: callback, alias, deprecated, internalOnly
      def register(name, handler, **metadata) = raise NotImplementedError
      def get(name) = raise NotImplementedError
      def has?(name) = raise NotImplementedError
    end
  end
end
```

**Platform Extensions:**

| Platform | Environment Extensions | Registry Metadata |
|----------|----------------------|-------------------|
| ST | `instruct_config`, `clock`, `rng`, `content_hash`, `chat_id_hash`, `global_offset`, `extensions` | `type`, `arity`, `strictArgs`, `delayArgResolution`, `list` |
| RisuAI | `chat_index`, `toggles`, `metadata` (15+ keys), `modules`, `assets`, `greeting_index` | `callback`, `alias`, `deprecated`, `internalOnly` |

---

### 2. Lore::Engine::Base

Accepts a `ScanInput` parameter object instead of positional arguments. ST
passes scan_context + timed_state; RisuAI passes store + message_index
+ recursive flag.

```ruby
module TavernKit::Lore
  module Engine
    class Base
      # @param input [Lore::ScanInput] platform-specific scan context
      # @return [Lore::Result] activation results
      def scan(input) = raise NotImplementedError
    end
  end

  # Minimal shared scan input -- platforms extend via subclass
  class ScanInput
    attr_reader :messages, :books, :budget

    def initialize(messages:, books:, budget:, **_platform_attrs)
      @messages = messages
      @books = books
      @budget = budget
    end
  end
end
```

**Platform Extensions:**

| Platform | ScanInput Extensions |
|----------|---------------------|
| ST | `scan_context` (persona/desc/personality/depth_prompt/scenario/creator_notes), `scan_injects` (Author's Note + extension prompts), `trigger` (generation type), `timed_state`, `character_filter`, `forced_activations`, `min_activations`, `min_activations_depth_max` |
| RisuAI | `store`, `message_index`, `recursive_scanning`, `greeting_index` |

---

### 3. Lore::Entry Strategy

Minimal shared schema + `extensions` Hash for platform-specific fields:

**Core Fields:**
- `keys` (primary keywords)
- `content`
- `enabled`
- `insertion_order`
- `id`

**Platform Extensions via `extensions` Hash:**

| Platform | Extensions |
|----------|-----------|
| ST | `match_persona_description`, `match_character_description`, `match_character_personality`, `match_character_depth_prompt`, `match_scenario`, `match_creator_notes`, `character_filter`, `triggers`, `selective_logic`, `secondary_keys`, `use_probability`, `probability`, `sticky`, `cooldown`, `delay`, `group_override`, `group_weight`, etc. (40+ fields) |
| RisuAI | Runtime decorator parsing from `content` — no persistent extensions needed |

---

### 4. VariablesStore::Base

Adds `scope:` parameter. Core guarantees `:local` and `:global`; RisuAI extends
with `:temp` and `:function_arg`.

```ruby
module TavernKit
  class VariablesStore::Base
    CORE_SCOPES = %i[local global].freeze

    def get(name, scope: :local) = raise NotImplementedError
    def set(name, value, scope: :local) = raise NotImplementedError
    def has?(name, scope: :local) = raise NotImplementedError
    def delete(name, scope: :local) = raise NotImplementedError
    def add(name, value, scope: :local) = raise NotImplementedError
  end
end
```

**Scope Comparison:**

| Scope | ST | RisuAI | Persistence |
|-------|-----|--------|-------------|
| `:local` | `setvar`/`getvar`/`addvar`/`incvar`/`decvar`/`hasvar`/`deletevar` | `setvar`/`getvar`/`addvar`/`setdefaultvar` | Per-chat |
| `:global` | `setglobalvar`/`getglobalvar` + global variants | `getglobalvar` (read-only in CBS) + toggles (`toggle_` prefix) | Cross-chat |
| `:temp` | ❌ | `settempvar`/`tempvar` | Per-parse-cycle (ephemeral) |
| `:function_arg` | ❌ | `{{arg::0}}` | Per `#func` call (stack-scoped, 20 depth limit) |

---

### 4b. ChatHistory::Base

Chat history is a **prompt-building data source**, not a chat UI model. Core
needs a minimal, predictable contract that works for both in-memory arrays and
ActiveRecord-backed iterators.

**Contract (Core):**
- `ChatHistory::Base` includes `Enumerable`.
- `#each` yields messages in **chronological order** (oldest -> newest).
- Yielded messages should be `Prompt::Message` (recommended) or at least duck-
  type as `{ role:, content: }`.

```ruby
module TavernKit
  module ChatHistory
    class Base
      include Enumerable

      def append(message) = raise NotImplementedError
      def each(&block) = raise NotImplementedError
      def size = raise NotImplementedError
      def clear = raise NotImplementedError

      # Optional performance overrides: #last(n), *_message_count
    end
  end
end
```

**Message model contract (Core):**
- Required: `role: Symbol`, `content: String`
- Optional: `name: String`, `send_date: Time/Date/DateTime/Numeric/String`
- Optional ST/RisuAI state lives in `Prompt::Message#metadata` (e.g., swipe
  info, provider/tool-call passthrough, app-specific IDs).

Core and platform layers may derive "message id" semantics from the **index in
the yielded sequence** (0-based) unless a platform chooses to expose a stable
identifier via `message.metadata[:id]`.

**Performance note:** adapters may override `#last(n)`/`#size`/`*_message_count`
to avoid materializing the full history (ActiveRecord windowing).

**Ergonomics:** Core should provide `ChatHistory.wrap(input)` to accept nil,
arrays, or enumerable-like inputs and coerce hashes into `Prompt::Message`.

---

### 4c. Preset::Base (Token Budget Contract)

Core needs a minimal, provider-agnostic budget contract. Platform layers add
their own configuration surfaces, but Core only requires the numbers needed for
token budgeting.

```ruby
module TavernKit
  module Preset
    class Base
      def context_window_tokens = raise NotImplementedError
      def reserved_response_tokens = raise NotImplementedError

      def max_prompt_tokens
        context_window_tokens.to_i - reserved_response_tokens.to_i
      end
    end
  end
end
```

---

### 4d. HookRegistry::Base (Build-time Hooks)

Hooks are optional build-time interception points used by the application layer
and/or platform layers (mirrors ST extension interception).

Core contract should support:
- register hooks (`#before_build`, `#after_build`)
- run hooks (`#run_before_build`, `#run_after_build`)

Hook contexts are platform-defined (Core treats them as opaque objects with
known accessors).

---

### 4e. InjectionRegistry::Base (Programmatic Injections)

Programmatic injections are a data-model for features like STscript `/inject`:
register by id, position mapping, optional scan/ephemeral flags.

Core contract should support:
- `#register(id:, content:, position:, **opts)` (idempotent replace by id)
- `#remove(id:)`
- `#each` yields injection entries
- `#ephemeral_ids` for one-shot pruning after a build

---

### 5. Prompt::Block Validation Relaxation

Relax validation for cross-platform support:

**ROLES:**
- Current: `%i[system user assistant]`
- Add: `:tool` / `:function` (Core can represent tool calls/results; dialect converters handle provider-specific mapping)

**REMOVABLE:**
- Add `removable: true/false` flag (default `true`)
- Rationale: both ST and RisuAI need hard protections (system prompt/PHI/latest user msg) even when trimming

**INSERTION_POINTS:**
- Current: whitelist of 8 ST-specific points
- Change: type-check only (`Symbol` required, no fixed set)
- Rationale: RisuAI uses `@position pt_custom_name`, `:before_desc`,
  `:after_desc`, `:personality`, `:scenario`, etc.

**BUDGET_GROUPS:**
- Current: `%i[system examples lore history custom default]`
- Change: type-check only (`Symbol` required, no fixed set)
- Rationale: RisuAI uses priority-based eviction, not fixed group names

---

### 6. Prompt::Message Forward Compatibility

Reserve optional fields for multimodal and metadata passthrough:
- `multimodals` / `attachments` (images/audio/video payloads)
- `metadata` (tool calls/tool results, cache hints, provider-specific fields)

Dialect converters should **preserve passthrough fields** whenever possible.
In the Core-only phase (before Dialects exist), `Plan#to_messages` may return
minimal OpenAI-like hashes (role/content/name) and therefore drop passthrough
fields; use explicit serialization helpers for persistence.

---

### 7. Trimmer

Add pluggable eviction strategy:

```ruby
class Trimmer
  # :group_order (ST default) -- examples > lore > history
  # :priority (RisuAI) -- sort by block.priority, evict lowest first
  def initialize(strategy: :group_order)
  def trim(blocks, budget:, estimator:) -> TrimResult
end
```

**Strategy Comparison:**

| Aspect | `:group_order` (ST) | `:priority` (RisuAI) |
|--------|---------------------|---------------------|
| Order | `:system` > `:examples` > `:lore` > `:history` | Sort by `block.priority` descending |
| Eviction unit | Examples as whole dialogues; history oldest-first | Individual blocks |
| Protection | `:system` never evicted; preserve latest user message | `removable: false` flag; `@ignore_on_max_context` sets priority -1000 |

#### 7a. TrimResult and TrimReport

**TrimResult** is the return value of `Trimmer#trim`:

```ruby
module TavernKit
  # Immutable result of a trim operation.
  TrimResult = Data.define(:kept, :evicted, :report) do
    # @return [Array<Block>] blocks retained in the prompt
    # @return [Array<Block>] blocks evicted due to budget
    # @return [TrimReport] detailed report for debugging/observability
  end

  # Detailed trim report for debugging and observability.
  TrimReport = Data.define(
    :strategy,           # Symbol - :group_order or :priority
    :budget_tokens,      # Integer - max tokens allowed
    :initial_tokens,     # Integer - tokens before trimming
    :final_tokens,       # Integer - tokens after trimming
    :eviction_count,     # Integer - number of blocks evicted
    :evictions           # Array<EvictionRecord> - per-block eviction details
  ) do
    def tokens_saved = initial_tokens - final_tokens
    def over_budget? = initial_tokens > budget_tokens
  end

  # Per-block eviction record.
  EvictionRecord = Data.define(
    :block_id,           # String - block.id
    :slot,               # Symbol, nil - block.slot
    :token_count,        # Integer - tokens in this block
    :reason,             # Symbol - :budget_exceeded, :group_overflow, :priority_cutoff
    :budget_group,       # Symbol - block.token_budget_group
    :priority,           # Integer - block.priority (for :priority strategy)
    :source              # Hash, nil - block.metadata[:source] for provenance
  )
end
```

**Usage in Lore::Result:**

`Lore::Result` should also include a `TrimReport` when budget enforcement
applies during lore activation:

```ruby
module TavernKit::Lore
  Result = Data.define(
    :activated_entries,  # Array<Entry> - entries that matched and fit budget
    :total_tokens,       # Integer - total tokens of activated entries
    :trim_report         # TrimReport, nil - if budget trimming occurred
  )
end
```

---

### 8. TokenEstimator

Pluggable adapter interface with optional model hint:

```ruby
class TokenEstimator
  def estimate(text, model_hint: nil) -> Integer
end
```

---

### 8b. Dialects (Output Conversion)

Core API uses a **symbol dialect selector**:

- `Plan#to_messages(dialect: :openai, **opts)` (default: `:openai`)
- Dialect conversion should be implemented as `TavernKit::Dialects.convert(messages, dialect:, **opts)`

This keeps the public surface small and matches how Rails app callers typically
switch providers.

**Extensibility (low ceremony):**
- Downstream apps can add a custom dialect by extending the `TavernKit::Dialects`
  registry/case statement once it lands (no need to thread a dialect object
  through the entire build).

---

### 9. Prompt::Context

`Prompt::Context` is a **mutable build workspace** that flows through the
middleware pipeline. Middlewares mutate `ctx` directly; branching/what-if is
done via `ctx.dup` (shallow copy). Output value objects (`Prompt::Block`,
`Prompt::Message`, `Prompt::Plan`) should remain immutable.

Note: output immutability is currently **shallow**. Objects are frozen, but
nested values may still be mutable depending on construction. Treat nested
values as read-only by convention, and tighten boundaries as Dialects and
platform layers land.

Current ST-flavored accessors should migrate to `metadata` hash access in
continued platform-agnostic cleanup:

**Current (ST-specific):**
- `pinned_groups`, `outlets`, `prompt_entries`, `scan_context`,
  `scan_injects`, `forced_world_info_activations`

**Target (platform-agnostic):**
- `ctx[:pinned_groups]`, `ctx[:template_cards]`, `ctx[:trigger_state]`, etc.

This is a non-blocking optimization; the existing `metadata` hash already
supports platform-specific storage.

---

### 10. Pipeline Observability & Debuggability

TavernKit is used to build prompts for roleplay/writing/agent workflows where
it is critical to understand:
- how the final prompt is composed (provenance)
- why content was trimmed/evicted (budget compliance)
- whether output is stable enough to cache (fingerprinting)

Core should provide optional instrumentation with **no ActiveSupport
dependency**:

- `Prompt::Instrumenter` interface (callable) receives events:
  `:middleware_start`, `:middleware_finish`, `:middleware_error`, `:warning`,
  `:stat`, plus budget/trim events.
- `Prompt::Trace` value object collects stage timings and key counters
  (block counts, token estimates, warnings, evictions) and a stable prompt
  fingerprint derived from final output messages (excluding random block ids).
- Blocks should carry provenance in `block.metadata[:source]` (e.g.,
  `{ stage: :lore, id: "wi:entry_123" }`) so traces and trim reports can explain
  *why* content exists in the final prompt.
- Middleware exceptions should be wrapped as a `PipelineError` that includes
  the failing stage name and original error to make production debugging
  actionable.

This should be opt-in (off by default) so production overhead is controllable.

#### 10a. Trace and Instrumenter Design

```ruby
module TavernKit
  module Prompt
    # Per-stage trace record.
    TraceStage = Data.define(
      :name,             # Symbol - middleware/stage name
      :duration_ms,      # Float - execution time
      :stats,            # Hash - stage-specific counters (symbol keys)
      :warnings          # Array<String> - warnings emitted during this stage
    )

    # Complete pipeline trace.
    Trace = Data.define(
      :stages,           # Array<TraceStage>
      :fingerprint,      # String - SHA256 of final prompt content (for caching)
      :started_at,       # Time
      :finished_at,      # Time
      :total_warnings    # Array<String> - all warnings (aggregated from stages + context)
    ) do
      def duration_ms = (finished_at - started_at) * 1000
      def success? = stages.none? { |s| s.stats[:error] }
    end

    # Simple callable interface (Proc-compatible).
    module Instrumenter
      class Base
        # @param event [Symbol] event type
        # @param payload [Hash] event-specific data (symbol keys)
        def call(event, **payload) = raise NotImplementedError
      end

      # Default no-op instrumenter (optional).
      # Production default should be `nil` to avoid instrumentation overhead.
      class Null < Base
        def call(event, **payload) = nil
      end

      # Trace-collecting instrumenter for debugging.
      class TraceCollector < Base
        attr_reader :stages, :warnings

        def initialize
          @started_at = Time.now
          @stages = []
          @warnings = []
          @stage_warnings = Hash.new { |h, k| h[k] = [] }
          @stage_stats = Hash.new { |h, k| h[k] = {} }
          @current_stage = nil
          @stage_start = nil
        end

        def call(event, **payload)
          case event
          when :middleware_start
            @current_stage = payload[:name]
            @stage_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            @stage_warnings[@current_stage] = []
            @stage_stats[@current_stage] = {}
          when :middleware_finish
            duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @stage_start) * 1000
            @stages << TraceStage.new(
              name: @current_stage,
              duration_ms: duration,
              stats: @stage_stats[@current_stage].merge(payload[:stats] || {}),
              warnings: @stage_warnings[@current_stage].dup
            )
          when :warning
            @warnings << payload[:message]
            stage = payload[:stage] || @current_stage
            @stage_warnings[stage] << payload[:message] if stage
          when :stat
            stage = payload[:stage] || @current_stage
            key = payload[:key]
            @stage_stats[stage][key.to_sym] = payload[:value] if stage && key
          when :middleware_error
            @stages << TraceStage.new(
              name: @current_stage,
              duration_ms: 0,
              stats: @stage_stats[@current_stage].merge(error: payload[:error].class.name),
              warnings: @stage_warnings[@current_stage].dup
            )
          end
        end

        def to_trace(fingerprint:)
          finished_at = Time.now
          Trace.new(
            stages: @stages.freeze,
            fingerprint: fingerprint,
            started_at: @started_at,
            finished_at: finished_at,
            total_warnings: @warnings.freeze
          )
        end
      end
    end
  end
end
```

**Debug switch (Core):**
- `context.instrumenter` is `nil` by default (production).
- Debug builds set `context.instrumenter = Instrumenter::TraceCollector.new`.
- Middleware authors can emit stage-local stats via `ctx.instrument(:stat, key: ..., value: ...)`
  (and optionally `stage:` when emitting from nested helpers).
- Provide a helper that supports lazy payload evaluation so middleware authors
  can attach expensive debug data without impacting production:

```ruby
class TavernKit::Prompt::Context
  attr_accessor :instrumenter

  def instrument(event, **payload)
    return nil unless @instrumenter

    if block_given?
      @instrumenter.call(event, **payload.merge(yield))
    else
      @instrumenter.call(event, **payload)
    end
  end
end
```

#### 10b. Integration with Context#warnings

`Prompt::Context#warn` should emit to both the warnings array AND the
instrumenter (if present):

```ruby
class TavernKit::Prompt::Context
  def warn(message)
    msg = message.to_s
    @warnings << msg

    instrument(:warning, message: msg, stage: @current_stage)

    if @strict
      raise TavernKit::StrictModeError, msg
    end

    effective_warning_handler&.call(msg)
    nil
  end
end
```

This ensures warnings appear in both:
- `context.warnings` (for programmatic access)
- `trace.stages[n].warnings` (for per-stage debugging)
- `trace.total_warnings` (for summary)

---

### 11. Error Handling Strategy

TavernKit uses a layered error handling approach: warnings for recoverable
issues, exceptions for unrecoverable failures.

#### 11a. Error Hierarchy

```ruby
module TavernKit
  # Base error class for all TavernKit errors.
  class Error < StandardError; end

  # === Core Errors ===

  # Card parsing/validation failures.
  class InvalidCardError < Error; end

  # Unsupported card format/version.
  class UnsupportedVersionError < Error; end

  # PNG parsing failures.
  module Png
    class ParseError < Error; end
    class WriteError < Error; end
  end

  # Lore parsing failures.
  module Lore
    class ParseError < Error; end
  end

  # Strict mode: warnings become errors.
  class StrictModeError < Error; end

  # Pipeline execution failures (wraps stage errors).
  class PipelineError < Error
    attr_reader :stage

    def initialize(message, stage:)
      @stage = stage
      super("#{message} (stage: #{stage})")
    end
  end

  # Token budget exceeded and cannot recover.
  class TokenBudgetExceeded < Error
    attr_reader :budget, :actual

    def initialize(budget:, actual:)
      @budget = budget
      @actual = actual
      super("Token budget exceeded: #{actual} > #{budget}")
    end
  end

  # === SillyTavern Errors ===
  module SillyTavern
    # Invalid ST preset format/fields.
    class InvalidPresetError < Error; end

    # Macro expansion failures.
    class MacroError < Error
      attr_reader :macro_name, :position

      def initialize(message, macro_name: nil, position: nil)
        @macro_name = macro_name
        @position = position
        super(message)
      end
    end

    # Macro syntax errors (malformed `{{...}}`).
    class MacroSyntaxError < MacroError; end

    # Unknown macro name.
    class UnknownMacroError < MacroError; end

    # Unmatched macro placeholders after expansion.
    class UnconsumedMacroError < MacroError; end

    # Lore/World Info parsing failures (ST-specific).
    class LoreParseError < Error; end

    # Invalid instruct format.
    class InvalidInstructError < Error; end

    # Invalid context template.
    class InvalidContextTemplateError < Error; end
  end

  # === RisuAI Errors ===
  module RisuAI
    # CBS macro failures.
    class CBSError < Error
      attr_reader :position, :block_type

      def initialize(message, position: nil, block_type: nil)
        @position = position
        @block_type = block_type
        super(message)
      end
    end

    # CBS syntax errors.
    class CBSSyntaxError < CBSError; end

    # CBS function call depth exceeded (20 limit).
    class CBSStackOverflowError < CBSError; end

    # Decorator parsing failures.
    class DecoratorParseError < Error; end

    # Trigger execution failures.
    class TriggerError < Error
      attr_reader :trigger_type, :effect_type

      def initialize(message, trigger_type: nil, effect_type: nil)
        @trigger_type = trigger_type
        @effect_type = effect_type
        super(message)
      end
    end

    # Trigger recursion limit exceeded (10 limit).
    class TriggerRecursionError < TriggerError; end
  end
end
```

#### 11b. Warning vs Exception Decision Rules

| Situation | Strict Mode | Normal Mode | Rationale |
|-----------|-------------|-------------|-----------|
| **Unknown macro** (`{{unknown}}`) | `raise UnknownMacroError` | `warn` + preserve literal | User may have intentional placeholder |
| **Malformed macro syntax** (`{{broken`) | `raise MacroSyntaxError` | `warn` + preserve literal | Likely typo, preserve for debugging |
| **Unmatched placeholders after expansion** | `raise UnconsumedMacroError` | `warn` | Quality issue but recoverable |
| **Missing required context** (no character) | `raise ArgumentError` | `raise ArgumentError` | Cannot proceed without data |
| **Invalid card format** | `raise InvalidCardError` | `raise InvalidCardError` | Cannot parse, unrecoverable |
| **Middleware exception** | `raise PipelineError` | `raise PipelineError` | Always fatal, wrap with stage info |
| **Token budget exceeded** | `raise TokenBudgetExceeded` | Trim + `warn` | Recoverable via trimming |
| **Invalid preset field value** | `raise InvalidPresetError` | `warn` + use default | Config error, but can continue |
| **Lore entry parse error** | `raise LoreParseError` | `warn` + skip entry | One bad entry shouldn't kill build |
| **CBS block unclosed** | `raise CBSSyntaxError` | preserve (tolerant) | RisuAI keeps rendering by preserving raw tokens |
| **CBS stack overflow** (call stack > 20) | `raise CBSStackOverflowError` | inline `"ERROR: Call stack limit reached"` | Match RisuAI UI behavior; strict/debug should surface as an error |
| **Trigger recursion limit** (runtrigger > 10) | `raise TriggerRecursionError` | skip nested runtrigger | Match RisuAI behavior: prevent infinite loops without killing the render |

#### 11c. Strict Mode

Strict mode (`context.strict = true`) converts **quality-affecting warnings**
into exceptions:

```ruby
# In Context#warn
def warn(message)
  msg = message.to_s
  @warnings << msg

  instrument(:warning, message: msg, stage: @current_stage)
  raise TavernKit::StrictModeError, msg if @strict
  effective_warning_handler&.call(msg)
  nil
end
```

**Use strict mode for:**
- Tests (catch all quality issues)
- Card validation tools
- Debug builds

**Use normal mode for:**
- Production runtime (graceful degradation)
- User-facing applications

#### 11d. Pipeline Error Wrapping

Middleware exceptions should always be wrapped to include stage context:

```ruby
# Rack-style middleware chain: wrap errors at the stage boundary.
class TavernKit::Prompt::Middleware::Base
  def call(ctx)
    stage = self.class.middleware_name
    ctx.instance_variable_set(:@current_stage, stage)

    ctx.instrument(:middleware_start, name: stage)

    before(ctx)
    @app.call(ctx)
    after(ctx)

    ctx.instrument(:middleware_finish, name: stage, stats: {})
    ctx
  rescue StandardError => e
    ctx.instrument(:middleware_error, name: stage, error: e)
    raise TavernKit::PipelineError.new(e.message, stage: stage), cause: e
  ensure
    ctx.instance_variable_set(:@current_stage, nil)
  end
end
```

---

## Related Docs

- Contracts: `lib/tavern_kit/docs/contracts/prompt-orchestration.md`
- Compatibility matrices:
  - SillyTavern: `lib/tavern_kit/docs/compatibility/sillytavern.md`
  - RisuAI: `lib/tavern_kit/docs/compatibility/risuai.md`
- Audit notes:
  - Rewrite audit: `lib/tavern_kit/docs/rewrite-audit.md`
  - Security/perf audit: `lib/tavern_kit/docs/security-performance-audit.md`

## API Style Guidelines

### Ruby Idiomatic Patterns

#### 1. Normalize Inputs, Fail-fast at Boundaries

Prefer small normalization (`to_sym`/`to_s`) and raise descriptive errors at
boundaries. Use duck typing internally, but avoid leaking `NoMethodError` to
callers.

```ruby
# ✓ Normalize, raise helpful errors at boundaries
def initialize(role:)
  @role = role.to_sym
rescue NoMethodError
  raise ArgumentError, "role must be symbol-like (responds to #to_sym)"
end
```

#### 2. Fluent Immutable Updates

Value objects should support `#with(**attrs)` for immutable updates:

```ruby
# Supported pattern
new_block = block.with(enabled: false, priority: 50)

# Also support convenience methods
disabled_block = block.disable
high_priority = block.with_priority(200)
```

#### 3. Named Parameters for Complex Constructors

Use keyword arguments for constructors with 3+ parameters:

```ruby
# ✓ Clear intent
Block.new(
  role: :system,
  content: "Hello",
  insertion_point: :relative,
  priority: 100
)

# ✗ Positional confusion
Block.new(:system, "Hello", :relative, 100)
```

#### 4. Builder Pattern for Complex Configuration

Consider Builder for objects with many optional parameters:

```ruby
# For Pipeline/Context configuration
ctx = Context.build do |b|
  b.character my_char
  b.user my_user
  b.preset my_preset
  b.strict true
end

# Alternative: DSL block (already used in TavernKit.build)
plan = TavernKit::SillyTavern.build do
  character my_char
  user my_user
  message "Hello!"
end
```

#### 5. Module Aliasing for Deep Namespaces

Provide shortcuts sparingly for very deep namespaces (usually engines/parsers),
to keep call sites readable.

```ruby
# In lib/tavern_kit/silly_tavern/silly_tavern.rb
module TavernKit
  module SillyTavern
    MacroV2 = Macro::V2Engine
  end
end

# Usage:
engine = TavernKit::SillyTavern::MacroV2.new
```

#### 6. Predicate Methods

Use `?` suffix for boolean queries:

```ruby
block.enabled?      # not block.is_enabled
block.removable?    # not block.can_remove
context.strict?     # not context.strict_mode
plan.greeting?      # not plan.has_greeting
```

#### 7. Bang Methods for Mutation/Danger

Use `!` suffix for in-place mutation or operations that raise:

```ruby
context.validate!   # raises if invalid
entry.activate!     # mutates state (if mutable)
```

### Naming Conventions

| Pattern | Example | Usage |
|---------|---------|-------|
| `to_*` | `to_h`, `to_message`, `to_json` | Conversion methods |
| `*?` | `enabled?`, `valid?` | Boolean predicates |
| `*!` | `validate!`, `save!` | Dangerous/mutating operations |
| `with_*` | `with(attrs)`, `with_priority(n)` | Immutable update |
| `from_*` | `from_hash`, `from_json` | Factory methods |

---

## Reference

- ST alignment delta: `lib/tavern_kit/docs/compatibility/sillytavern-deltas.md`
- RisuAI alignment delta: `lib/tavern_kit/docs/compatibility/risuai-deltas.md`
