# TODO: Native Multilingual Support via Language Policy (Middleware Plan)

Goal: add **native**, configurable multilingual support to `TavernKit::VibeTavern`
so the model can reply in the **user’s preferred language** even when Character,
Lorebook, or other context is written in a different language — while keeping
**tool calling** and **structured directives** correct.

Key constraint: if the assistant output contains **machine-readable segments**
(tool calls, directives JSON, code blocks, special tags/macros), those segments
must be preserved **verbatim** and must not be “translated” or localized.

This repo does **not** add an app-level content/ethics policy in the infra
layer. Any safety guardrails remain the responsibility of the upstream LLM /
provider. This middleware must stay focused on:
- output language and style constraints
- protocol correctness (tools/directives)
- “verbatim zones” preservation

This is a product-facing backlog item. It builds on:
- Architecture: `docs/research/vibe_tavern/architecture.md`
- Tool calling: `docs/research/vibe_tavern/tool-calling.md`
- Structured directives: `docs/research/vibe_tavern/directives.md`
- Reference translation roadmap (Playground): `resources/tavern_kit/playground/docs/CONVERSATION_TRANSLATION_PLAN.md`

## Why “native” multilingual (instead of post-translation)

We want a mode where:
- chat remains **streaming** (no “translate after” delay)
- the assistant writes directly in the target language, with natural phrasing
- we do not assume the entire conversation is English (unlike ST’s translate
  extension, which primarily translates displayed text)

This should be treated as an **output policy** at the prompt level, not as a
separate translation subsystem.

## What “native multilingual support” means (contract)

Given a request-scoped config `target_lang`:

1) **Assistant natural language is in `target_lang`**
   - “Natural language” includes `assistant_text` in directives envelope, and
     the final assistant message after tool calls complete.
   - The assistant should prefer idiomatic, native phrasing (localization),
     not literal word-for-word translation.

2) **Verbatim zones are not translated**
   - Anything that is “code” or “protocol” must be reproduced exactly.
   - If the user provides tags/macros/placeholders, keep them unchanged.

3) **Tool calling correctness is preserved**
   - Tool names, JSON keys, ids, and structured arguments must never be
     translated or renamed.
   - The language policy must not encourage “extra explanatory text” in tool
     call turns.

4) **Structured directives correctness is preserved**
   - Envelope keys (`assistant_text`, `directives`, `type`, `payload`) are fixed.
   - Directive `type` strings are app-defined and must remain canonical.
   - Only the human-facing strings (primarily `assistant_text`) should be
     language-constrained.

Non-goals (for P0):
- full UI i18n via Rails `I18n.t`
- a “Translate both” mode (ST-style) inside `lib/tavern_kit/vibe_tavern`
- shipping external translation providers (DeepL/Google/etc) inside the infra layer
  - Note: an app-owned “final answer translate” fallback is allowed for
    non-streaming runs (tool loop + directives).

## Priority order (tool calls first)

When goals conflict, prefer **protocol reliability** over language purity:

- Tool calling: tool-call success rate is the #1 priority.
  - Language policy must not reduce tool-call correctness.
  - If the final answer is not in `target_lang`, apply an optional post-pass
    translate/rewrite fallback (non-streaming only).
- Directives: envelope validity + canonical directive types are the #1 priority.
  - Language policy should primarily constrain `assistant_text`.
  - Payload language enforcement is app-owned (optional validators).

## Fit with current VibeTavern architecture

Single-request boundary:
- `lib/tavern_kit/vibe_tavern/prompt_runner.rb`

Prompt-building pipeline:
- `lib/tavern_kit/vibe_tavern/pipeline.rb`
- `lib/tavern_kit/vibe_tavern/middleware/prepare.rb`
- `lib/tavern_kit/vibe_tavern/middleware/plan_assembly.rb`

Protocols:
- Tool loop: `lib/tavern_kit/vibe_tavern/tool_calling/tool_loop_runner.rb`
- Directives runner: `lib/tavern_kit/vibe_tavern/directives/runner.rb`

Recommended approach:
- implement “target language output” as a **pipeline middleware** that injects
  a small **Language Policy** system block into the prompt plan.
- keep it app-configurable via `runtime` (preferred) or prompt context metadata.

Why middleware:
- it works for chat-only streaming, directives runs, and tool loop runs
  uniformly (all use `PromptRunner#build_request` → `TavernKit::VibeTavern.build`)
- it avoids scattering “respond in X” instructions across call sites

## Proposed configuration surface (runtime-owned)

Store this under the request-scoped runtime snapshot:

`runtime[:language_policy]`

Minimum fields (P0):
- `enabled`: boolean
- `target_lang`: string (BCP-47, strict allowlist; see “Language codes”)

Optional fields (P1+):
- `style_hint`: string (e.g. “colloquial”, “literary”, “formal”)
- `glossary`: array of `{ src, dst }` terminology pairs (hit-based injection)
- `ntl`: “no translate list” (literal/regex patterns; hit-based injection)
- `verbatim_rules`: allowlist of protected syntaxes (see next section)
- `special_tags`: array of tag names (app-injected; e.g. `["think", "a2ui"]`)
- `allow_language_switch`: boolean (let the user ask for a different output
  language for a single turn)

Language policy is **app-owned configuration**:
- users set the preference in product UI/settings
- the app computes precedence (e.g. membership > space) and injects a single
  `target_lang` into `runtime[:language_policy]`
- `TavernKit::VibeTavern` does not derive language preference from chat text

## Language codes (strict, allowlisted BCP-47)

For reliability, enforce **BCP-47 codes only** and support a small allowlist.
Treat `zh-CN` vs `zh-TW` as distinct (not “same-lang”).

Supported tiers (current preference):

- Tier 1: `en-US`
- Tier 2: `zh-CN`, `zh-TW`, `ko-KR`, `ja-JP`
- Tier 3: `yue-HK`

Policy (P0 recommendation):
- If `target_lang` is not in the allowlist, disable language policy for that run
  and emit a warning/trace event at the app boundary (do not guess).
- Canonicalize common case variants (`zh-cn` → `zh-CN`) **before** allowlist
  checks (app-side preferred).
- Tier 2 enforcement is “language-shape” best-effort:
  - do not require semantic correctness (we don't need to "know the language")
  - allow only high-confidence checks (script/character distribution), otherwise warn
  - if a non-streaming post-pass rewrite/translate fallback is enabled, use it
    when output clearly drifts from `target_lang`
- Tier 3 enforcement is **best-effort**:
  - allow `yue-HK` as a target language (so prompts can request it)
  - do not hard-fail runs based on “is the content truly Cantonese” checks
  - still enforce all protocol/verbatim invariants (tools/directives/JSON/tags/URLs)

## Verbatim zones (must-preserve contract)

The middleware must define (and document) the “verbatim zones” that are never
to be translated/localized. Recommended initial set:

- fenced code blocks: triple backticks (```...```)
- inline code: backticks (`...`)
- Liquid macro syntaxes:
  - `{{ ... }}` and `{% ... %}` (see `docs/research/vibe_tavern/macros.md`)
- HTML/XML tags and attributes: `<...>` (treat as verbatim by default)
- structured directives JSON (when used):
  - keys: `assistant_text`, `directives`, `type`, `payload`
  - directive types are canonical strings (not translated)
- tool calling JSON:
  - tool names, JSON keys, ids, paths, op names (not translated)
- “special tags/markers” (app-defined):
  - e.g. `<think>`, `<tool>`, `<a2ui>`, or other XML-ish tags if the app uses
    them in prompts/outputs
- Markdown links/URLs (treat as verbatim by default):
  - bare URLs: `https://example.com`
  - autolinks: `<https://example.com>`
  - Markdown links: `[label](https://example.com)`

Important: for native multilingual mode we are not running a translator, so
this is a **generation-time constraint** (prompt policy), not a mask/unmask
post-process.

## Middleware design: `LanguagePolicy`

Add a new middleware:
- `lib/tavern_kit/vibe_tavern/middleware/language_policy.rb`

Pipeline insertion:
- `lib/tavern_kit/vibe_tavern/pipeline.rb` should `use ...LanguagePolicy`
  after `:plan_assembly` (because `PlanAssembly` finalizes `ctx.plan`).

Behavior (P0):
1) Read config from `ctx.runtime` (preferred) or `ctx[:language_policy]`.
2) If `enabled` and `target_lang` present:
   - Insert a new **system block** near the end of system instructions,
     ideally **after** post-history instructions and **before** the current user
     message block.
3) Rebuild `ctx.plan` with the modified blocks (since `PlanAssembly` already
   freezes the plan).

Suggested injected text (example, keep it short in production):

```text
Language Policy:
- Respond in: zh-CN. Use natural, idiomatic phrasing.
- Do not translate or alter any content inside code blocks, inline code, or
  special tags/macros ({{...}}, {%...%}), or HTML/XML tags (<...>).
- Do not translate or alter URLs or Markdown links.
- If you produce tool calls or JSON envelopes, keep tool names, directive types,
  and JSON keys exactly as specified. Do not add extra non-JSON text when JSON
  output is required.
- When calling tools, output tool calls only (no natural-language content).
```

Notes:
- The directives runner already adds strict “JSON only” instructions
  (`ENVELOPE_OUTPUT_INSTRUCTIONS`). LanguagePolicy must be compatible with that:
  it should constrain the *language of* `assistant_text`, not the envelope shape.
- Tool calling turns may require “tool calls only”. LanguagePolicy must not
  encourage extra text during tool-call turns.

## Hard problems / risks (and how to de-risk them)

### 1) Language drift (model replies in the wrong language)

Native mode can still drift, especially with mixed-language context.

De-risking options:
- P0: prompt-only guard + observability (log drift, no auto-rewrite)
- P1: add a lightweight language detector (heuristic) and allow an optional
  **rewrite/translate fallback** for non-streaming runs (tool loop + directives),
  preserving verbatim zones
- P2: “Hybrid” mode: detect drift and rewrite/translate display text, similar
  to the Playground plan

Important constraint:
- Chat-only streaming cannot be rewritten without breaking streaming UX.

### 2) Protocol corruption (tools/directives broken by localization)

Failure patterns:
- tool name translated (tool execution fails)
- JSON keys translated (parser fails)
- the model adds commentary around JSON (parser fails)

De-risking:
- Keep the language policy injection explicit about “protocol is verbatim”.
- For directives, keep `response_format` enabled where supported
  (`json_schema` → `json_object` → `prompt_only` fallback already exists).
- For tool calling, enforce “tool-call turns have empty content” at the
  tool-loop boundary (prompt-only is insufficient across providers).
- Add deterministic unit tests that assert the **prompt plan** includes the
  language policy block in all relevant runners, and that the directives runner
  continues to inject `response_format` unchanged.

#### Tool-call turn content policy (recommended)

Most stable approach: do **both** prompt guidance and hard enforcement.

1) Prompt guidance:
   - keep a short instruction: “When calling tools, output tool calls only
     (no natural-language content).”
2) Hard enforcement (infra/app boundary):
   - if an assistant message contains any `tool_calls`, do not feed any
     natural-language `content` back into the next-turn history
   - treat non-empty content as a warning/trace artifact (keep for debugging),
     but force `content` to `""` for the history message

Rationale:
- models/providers sometimes emit text alongside tool calls; it is frequently
  inconsistent with tool results and increases drift
- enforcement makes tool calling deterministic and reduces the chance that
  language policy “bleeds” into tool-call turns
- post-pass translation fallback applies only to the final assistant answer,
  never to tool-call turns

### 3) “Verbatim zones” are underspecified

We must decide what counts as “special tags” in VibeTavern output.

De-risking:
- Start with a conservative, easy-to-explain allowlist (code fences, inline
  code, Liquid macros, JSON envelopes, tool calls).
- Add app-defined extra protected patterns via config (P1).

### 4) Token cost / prompt noise

Long language rules, glossaries, and NTL lists can bloat prompts and reduce
reliability.

De-risking:
- Keep the base policy under ~15 lines.
- Inject glossary/NTL lines only when the source terms actually appear in the
  relevant prompt inputs (hit-based injection; see Playground plan).

## Development plan (ordered)

P0 (foundation, infra-only):
1) Implement `Middleware::LanguagePolicy` and wire it into the pipeline.
2) Define the runtime config contract (`runtime[:language_policy]`).
3) Add deterministic tests for:
   - enabled vs disabled
   - insertion position (before user message)
   - compatibility with directives runner system instructions
4) Add an eval dimension (post-implementation):
   - language policy enabled vs disabled
   - target languages: at least `zh-CN` and `ja-JP`
   - verify tool/directives protocol invariants do not regress

P1 (quality boosts, still “native” UX):
1) Optional “prompt component localization” (translate preset/character/lore
   blocks to `target_lang` ahead of the main streaming generation), cached.
2) Hit-based Glossary/NTL prompt injection for term stability.

P2 (hybrid fallback, non-streaming only):
1) Language drift detector + optional rewrite fallback for:
   - directives `assistant_text`
   - tool loop final assistant message
2) Observability: per-run drift stats in trace/events.

## Evaluation (planned)

Add “language policy on/off” as an explicit eval dimension for both protocols:

- Tool calling harness: `script/llm_tool_call_eval.rb`
  - primary metric: tool-scenarios success rate must not regress vs baseline
    (language policy disabled)
  - scenarios where the user message is non-English (e.g. `zh-CN`)
  - assert tool calls remain valid (tool name/args JSON untouched)
  - assert final assistant text is in `target_lang`
  - assert verbatim preservation (URLs/Markdown links/special tags) in the final answer
  - `yue-HK` note: treat “language correctness” as non-fatal; only require protocol/verbatim invariants
- Directives harness: `script/llm_directives_eval.rb`
  - assert envelope shape remains valid JSON
  - assert directive `type` strings remain canonical
  - assert `assistant_text` is in `target_lang`
  - (when app validators are enabled) assert user-visible payload strings are in `target_lang`
  - `yue-HK` note: treat “language correctness” as non-fatal; only require protocol/verbatim invariants

This is intentionally separate from any “Translate both” post-translation work:
we are measuring the **impact of the language policy prompt** on protocol
reliability.

## Acceptance criteria (P0)

- When `runtime[:language_policy].enabled == true`, chat responses are written
  in `target_lang` with natural phrasing.
- Tool calling still works:
  - tool names and JSON keys are not localized
  - the model can complete the loop and produce a final answer in `target_lang`
- Structured directives still work:
  - the envelope is valid JSON (no extra text)
  - `assistant_text` is in `target_lang`
  - directive `type` strings remain canonical
- No additional “ethics/safety policy” text is injected by this middleware.

## Decisions (current)

- Config naming: use `runtime[:language_policy]`.
- Language codes: strict BCP-47 allowlist (Tier 1–3 list above).
- Tier 2: best-effort “language-shape” validation (script/character distribution),
  not semantic correctness; prefer non-streaming post-pass fallback over hard fail.
- Tier 3 (`yue-HK`): include in allowlist, but only best-effort language validation (non-fatal).
- Group chat/multi-user: precedence is app-owned (membership > space); TavernKit
  receives only a single `target_lang` per run.
- Tool-call turns: enforce empty assistant content when `tool_calls` are present
  (prompt-only is insufficient for multi-provider reliability).
- Tool calling: tool-call success rate is the #1 priority; allow a post-pass
  final-answer translate/rewrite fallback when language drift occurs.
- Verbatim zones: treat HTML/XML tags and Markdown links/URLs as verbatim by
  default; Markdown code fences/inline code and Liquid macros are verbatim zones.
- Special tags: support an app-injected list of additional “special tags”
  via `runtime[:language_policy][:special_tags]`.
- Per-turn override: keep `target_lang` as strict app-only configuration.
- Directives payload: keep payload app-defined, but enforce (via app-owned
  validators) that user-visible payload strings are in `target_lang`.

## Open questions (remaining)

1) Directives payload validators:
   - define “user-visible strings” (schema metadata? allowlist of payload paths?)
   - choose a language detection strategy (heuristic vs LLM self-check)
2) App-side checkers:
   - add a deterministic “verbatim zone checker” suite similar to tool
     calling/directives evals (URL/tag preservation, code fence closure)
3) Post-pass translate/rewrite fallback:
   - define triggering (detector thresholds, allowlist-only, per-run toggle)
   - define translator prompt contract (verbatim zones, output constraints)
   - decide where it lives (app layer vs optional infra module)
