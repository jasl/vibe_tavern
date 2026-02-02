# Liquid Macros (VibeTavern)

This document records the **Liquid-based macro language** we plan to use for
the Rails rewrite's app-owned prompt pipeline (`TavernKit::VibeTavern`).

Goal: make templates feel close to ST/RisuAI “Handlebars-like” authoring, while
keeping a Ruby-native, testable implementation.

Scope:
- Liquid syntax reference (subset we rely on)
- the variables/objects exposed to templates
- the VariablesStore read/write API (our main divergence from ST/RisuAI macro syntax)
- references to upstream sources and compatibility docs

Non-goals:
- UI rendering
- DB/network/file I/O
- full SillyTavern or RisuAI macro parity (those are available via TavernKit's platform pipelines)

---

## 1) Liquid Syntax (Quick Reference)

Output:

```liquid
Hello, {{ user }}!
{{ description }}
```

Tags (control flow / statements):

```liquid
{% if var.mood == "happy" %}
  ...
{% elsif var.mood == "sad" %}
  ...
{% else %}
  ...
{% endif %}
```

Loops:

```liquid
{% for msg in history %}
  {{ msg.role }}: {{ msg.content }}
{% endfor %}
```

Assignment + capture:

```liquid
{% assign name = char %}
{% capture intro %}You are {{ char }}.{% endcapture %}
```

Filters:

```liquid
{{ "hello" | upcase }}
{{ "a,b,c" | split: "," | join: " / " }}
```

Comments:

```liquid
{% comment %}
This is ignored.
{% endcomment %}
```

Whitespace control (Liquid feature):
- `{%- ... -%}` trims surrounding whitespace. Use sparingly in prompts.

---

## 2) Template Environment (Assigns / Objects)

We expose a **small, prompt-building-safe** environment to Liquid. The exact
set of assigns will evolve, but the intent is:

Core text fields (Strings):
- `char`, `user`
- `description`, `personality`, `scenario`
- `persona`
- `system_prompt`, `post_history_instructions`
- `mes_examples` (raw; optionally also provide a formatted variant)

Runtime snapshot (read-only):
- `runtime` (object/Drop; built from `TavernKit::Runtime::Base`)
- common convenience fields may also be exposed at top-level:
  - `chat_index`, `message_index`, `model`, `role`

History (read-only):
- `history` (Array of message objects; shape depends on the app adapter)

VariablesStore (session-level state):
- `var` (local scope store; read-only in `{{ }}`)
- `global` (global scope store; read-only in `{{ }}`)

---

## 3) VariablesStore Design (Readable by Default)

We intentionally avoid “function-style getvar” APIs. Reads should look like
natural variable access.

Read local variables:

```liquid
{{ var.mood }}
{{ var.turns }}
{{ var["some-key"] }}
```

Read global variables:

```liquid
{{ global.score }}
{{ global["run_var"] }}
```

Behavior:
- Missing keys render as blank in tolerant mode.
- In strict mode, missing keys should surface as a warning/error (policy to be
  locked by tests once implemented).

Rationale:
- Readability and authoring ergonomics.
- Fewer quoting/escaping footguns compared to `getvar("mood")`.
- Avoids collisions with other macro names/functions.

---

## 4) VariablesStore Writes (Explicit Tags)

Writes are side effects. We make them explicit statements:

```liquid
{% setvar mood = "happy" %}
{% setglobal score = 10 %}
```

Suggested minimal tag set (local scope):
- `setvar name = value`
- `setdefaultvar name = value`
- `addvar name = value` (numeric add or string concat; match ST/RisuAI semantics)
- `incvar name` / `decvar name`
- `deletevar name`

Global variants:
- `setglobal name = value`
- `addglobal name = value`
- `incglobal name` / `decglobal name`
- `deleteglobal name`

Notes:
- Tags should accept expressions on the RHS (so `value` can be another variable).
- Tags should return empty output (statement semantics).

---

## 5) Strict vs Tolerant Mode

TavernKit has a pipeline-level `strict` mode used primarily for tests and debugging.

Liquid has its own “strict variables / strict filters” knobs. Our intent:
- tolerant mode: missing variables/macros degrade to empty output and/or warnings
- strict mode: missing variables/macros should be actionable (raise or strict warning)

Exact mapping will be finalized when the Liquid engine is implemented and
covered by characterization tests.

---

## 6) References

Liquid source copy:
- `resources/liquid` (vendored for reference/porting)

Liquid gem dependency:
- `Gemfile` (`gem "liquid"`)

Existing platform macro engines (for parity reference only):
- ST V2 engine: `vendor/tavern_kit/lib/tavern_kit/silly_tavern/macro/v2_engine.rb`
- RisuAI CBS engine: `vendor/tavern_kit/lib/tavern_kit/risu_ai/cbs/engine.rb`

Compatibility matrices:
- ST: `vendor/tavern_kit/docs/compatibility/sillytavern.md`
- RisuAI: `vendor/tavern_kit/docs/compatibility/risuai.md`

Rails rewrite pipeline docs:
- `docs/rewrite/vibe-tavern-pipeline.md`
- `docs/rewrite/rails-integration-guide.md`
