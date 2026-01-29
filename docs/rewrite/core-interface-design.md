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
| ChatVariables | **Medium** | Missing `temp`/`function_arg` scopes for RisuAI |
| Prompt::Block | **Low** | Missing `:function` role; `INSERTION_POINTS`/`BUDGET_GROUPS` too restrictive |
| Trimmer | **Low** | Needs pluggable strategy (`:group_order` vs `:priority`) |
| Pipeline/Middleware | **None** | Fully platform-agnostic; no changes needed |
| TokenEstimator | **None** | One interface sufficient; add optional `model_hint:` |
| Character/Card | **None** | `extensions` hash handles platform-specific fields |

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
passes scan_context + timed_state; RisuAI passes chat_variables + message_index
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
| ST | `scan_context` (persona/desc/personality/depth_prompt/scenario/creator_notes), `trigger` (generation type), `timed_state`, `character_filter`, `forced_activations`, `min_activations`, `min_activations_depth_max` |
| RisuAI | `chat_variables`, `message_index`, `recursive_scanning`, `greeting_index` |

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

### 4. ChatVariables::Base

Adds `scope:` parameter. Core guarantees `:local` and `:global`; RisuAI extends
with `:temp` and `:function_arg`.

```ruby
module TavernKit
  class ChatVariables::Base
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

### 5. Prompt::Block Validation Relaxation

Relax validation for cross-platform support:

**ROLES:**
- Current: `%i[system user assistant]`
- Add: `:function` (RisuAI `OpenAIChat` uses `role: 'function'`)

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

### 6. Trimmer

Add pluggable eviction strategy:

```ruby
class Trimmer
  # :group_order (ST default) -- examples > lore > history
  # :priority (RisuAI) -- sort by block.priority, evict lowest first
  def initialize(strategy: :group_order)
  def trim(blocks, budget:, estimator:) -> { kept:, evicted:, report: }
end
```

**Strategy Comparison:**

| Aspect | `:group_order` (ST) | `:priority` (RisuAI) |
|--------|---------------------|---------------------|
| Order | `:system` > `:examples` > `:lore` > `:history` | Sort by `block.priority` descending |
| Eviction unit | Examples as whole dialogues; history oldest-first | Individual blocks |
| Protection | `:system` never evicted; preserve latest user message | `removable: false` flag; `@ignore_on_max_context` sets priority -1000 |

---

### 7. TokenEstimator

Add optional model hint:

```ruby
class TokenEstimator
  def estimate(text, model_hint: nil) -> Integer
end
```

---

### 8. Prompt::Context

Current ST-flavored accessors should migrate to `metadata` hash access in
Wave 4 refactor:

**Current (ST-specific):**
- `pinned_groups`, `outlets`, `prompt_entries`, `scan_context`,
  `scan_injects`, `forced_world_info_activations`

**Target (platform-agnostic):**
- `ctx[:pinned_groups]`, `ctx[:template_cards]`, `ctx[:trigger_state]`, etc.

This is a non-blocking optimization; the existing `metadata` hash already
supports platform-specific storage.

---

## Implementation Priority

| Priority | Change | When |
|----------|--------|------|
| P0 | `Macro::Engine::Base` + `Environment::Base` | Wave 2 |
| P0 | `Lore::Engine::Base` + `ScanInput` | Wave 2 |
| P1 | `ChatVariables::Base` scope parameter | Wave 2 |
| P1 | `Block` validation relaxation | Wave 2 |
| P2 | `Trimmer` strategy parameter | Wave 4 |
| P2 | `Registry::Base` metadata parameter | Wave 2 |
| P3 | `Context` ST accessor migration | Wave 4 |

---

## Reference

- Roadmap: `docs/plans/2026-01-29-tavern-kit-rewrite-roadmap.md`
- ST alignment delta: `docs/rewrite/st-alignment-delta-v1.15.0.md`
- RisuAI alignment delta: `docs/rewrite/risuai-alignment-delta.md`
