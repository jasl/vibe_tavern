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

Escaping / literal braces:

- Liquid-native (recommended for large literals):

```liquid
{% raw %}
This will not be parsed: {{ var.mood }}
{% endraw %}
```

- ST-style (recommended for small inline escapes):
  - write `\{\{` and `\}\}` (or `\{` / `\}` generally)
  - our renderer unescapes `\{` → `{` and `\}` → `}` *after* Liquid renders

Example:

```liquid
\{\{ var.mood \}\}   ->   {{ var.mood }}
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

Note: `history` is intentionally **not exposed yet** in VibeTavern Liquid assigns.
When we add it, we will pin its shape with tests and document it here.

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
- `{%- ... -%}` trims surrounding whitespace/newlines around tags.
- `{{- ... -}}` trims surrounding whitespace/newlines around outputs.
- Use this instead of global whitespace stripping when authoring templates.

---

## 2) Template Environment (Assigns / Objects)

We expose a **small, prompt-building-safe** environment to Liquid.

Current assigns contract (implemented by `TavernKit::VibeTavern::LiquidMacros::Assigns.build(ctx)`):

Core text fields:
- `char` (character display name; uses nickname when present)
- `user` (user display name)
- `description`, `personality`, `scenario`
- `persona` (user persona text)
- `system_prompt`, `post_history_instructions`
- `mes_examples`

Runtime snapshot (read-only):
- `runtime` (Hash with **string keys**)
- `chat_index`, `message_index`, `model`, `role` (top-level conveniences; sourced from runtime)

Notes:
- History is intentionally not exposed yet. When/if we expose it, it will be
  read-only and its shape will be pinned by tests.

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

## 5) Filters (P0)

Deterministic RNG (prompt-building safe):

- `hash7` — stable 7-digit hash derived from input:

```liquid
{{ "hello" | hash7 }}
{{ "hello" | hash }} {# alias #}
```

- `pick` — deterministic pick based on runtime seeds:

```liquid
{{ "a,b,c" | pick }}
{{ "a,b,c" | split: "," | pick }}
```

Seeds used by default:
- `runtime.message_index` (as the deterministic counter; defaults to `0`)
- `runtime.rng_word` (as the deterministic seed word; falls back to `char`, then `"0"`)

Dice:

- `rollp` — deterministic dice roll (RisuAI-like):

```liquid
{{ "2d6" | rollp }}
```

Time/date helpers (UTC):

These filters accept epoch milliseconds (preferred) or seconds as input.
For deterministic builds, inject `runtime.now_ms` from the app.

```liquid
{{ runtime.now_ms | unixtime }}  {# -> "1700000000" #}
{{ runtime.now_ms | isodate }}   {# -> "2023-11-14" #}
{{ runtime.now_ms | isotime }}   {# -> "22:13:20" #}
{{ runtime.now_ms | datetimeformat: "YYYY-MM-DD HH:mm:ss" }}
```

`datetimeformat` supports a Moment-ish subset:
`YYYY YY MMMM MMM MM DDDD DD dddd ddd HH hh mm ss X x A`

---

## 6) Strict vs Tolerant Mode

TavernKit has a pipeline-level `strict` mode used primarily for tests and debugging.

Liquid has its own “strict variables / strict filters” knobs. Our intent:
- tolerant mode: missing variables/macros degrade to empty output and/or warnings
- strict mode: missing variables/macros should be actionable (raise or strict warning)

Current implementation (`TavernKit::VibeTavern::LiquidMacros.render`):
- `strict: false` renders with Liquid strictness disabled and **returns the
  original text** when Liquid raises (passthrough).
- `strict: true` (or `on_error: :raise`) raises `Liquid::Error` so tests/debug
  can fail fast.
- Safety limits:
  - Liquid templates are size-limited (today: 200KB) and rendered with resource
    limits to avoid runaway output/loops.
  - In tolerant mode, limit errors passthrough (return original text); in strict
    mode, they raise.

---

## 7) User Input Processing (Optional)

By default, we do **not** run Liquid macros on end-user messages.

If you want ST/RisuAI-style behavior (“user input also runs macros/scripts”),
apply it at the app layer **before persistence** (so what you store is what
you later show and feed back into prompt history).

We standardize on a simple toggle:
- `runtime[:toggles][:expand_user_input_macros]` (default: `false`)

Important:
- `runtime[:toggles]` must use **snake_case symbol keys**.
  We do not auto-normalize nested hashes inside runtime. If you load toggles
  from JSON, normalize keys before building runtime:

```ruby
toggles = json_toggles.to_h.transform_keys { |k| TavernKit::Utils.underscore(k).to_sym }
runtime = TavernKit::Runtime::Base.build({ toggles: toggles }, type: :app)
```

Helper:
- `TavernKit::VibeTavern::UserInputPreprocessor.call(text, variables_store:, runtime:, enabled: nil, strict:, on_error:)`

Notes:
- Enabling this means user-authored text can execute our write tags
  (`{% setvar %}`, `{% incvar %}`, etc) and mutate `variables_store`. Treat it
  as a deliberate feature flag (typically per-user/per-chat).
- “UI directives” (RisuAI-style) should stay app-owned and should be parsed
  **after** the LLM response, gated behind its own feature flag, and only from
  assistant-role output (never from user messages).

## 8) References

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
