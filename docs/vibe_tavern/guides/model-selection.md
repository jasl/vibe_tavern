# Model Selection (OpenRouter)

This repo evaluates “popular” OpenRouter models against the VibeTavern
infrastructure protocols:

- Tool calling (`ToolLoopRunner`)
- Structured directives (`Directives::Runner`)
- Native multilingual output policy (`PromptBuilder::Steps::LanguagePolicy`)

The intent is to pick **defaults** that keep **protocol reliability** high
across providers/models.

## Quick start (run the full suite)

```sh
OPENROUTER_LANGUAGE_POLICY_MATRIX=1 \
OPENROUTER_EVAL_PRESET=smoke \
OPENROUTER_MODEL_FILTER=stable \
OPENROUTER_SCENARIOS=simple \
OPENROUTER_TRIALS=1 \
OPENROUTER_JOBS=1 \
script/llm_vibe_tavern_eval.rb
```

Reports are written under:

- Tool calling: `tmp/llm_tool_call_eval_reports/<timestamp>/`
- Directives: `tmp/llm_directives_eval_reports/<timestamp>/`
- Language policy: `tmp/llm_language_policy_eval_reports/<timestamp>/`

## Current “stable” set (what `OPENROUTER_MODEL_FILTER=stable` means)

The eval scripts currently treat these as “stable” (as of 2026-02-09):

- `google/gemini-2.5-flash:nitro`
- `anthropic/claude-opus-4.6:nitro`
- `openai/gpt-5.2:nitro`
- `qwen/qwen3-30b-a3b-instruct-2507:nitro`
- `qwen/qwen3-next-80b-a3b-instruct:nitro`
- `qwen/qwen3-235b-a22b-2507:nitro`

Known caveats from the 2026-02-09 smoke run:

- Tool calling failures were entirely from `qwen/qwen3-next-80b-a3b-instruct:nitro`
  returning empty final completions (no HTTP error).
- Directives passed for all stable models, but some require workarounds (see the
  `MODEL_CATALOG` `workarounds:` in `script/llm_directives_eval.rb`).
- Language policy had a single empty `assistant_text` case (`openai/gpt-5.2:nitro`
  + `ja-JP` + `verbatim_zones`), which is why the eval harness retries empty
  responses by default.

## How to read reports

Start with:

- `summary.json` (per-model aggregates)
- `summary_by_scenario_and_language_policy.json` (quick regression scan for
  language policy on/off per scenario)

If something looks off, open the per-run JSON file from `run_results[*].report_path`
to see the trace/attempts (and the exact failure category).

## Recommendations

### Tool calling (reliability-first)

- Prefer models that pass `script/llm_tool_call_eval.rb` under the `production`
  strategy, with sequential tool calls (`parallel_tool_calls: false`).
- If a model returns empty completions during finalization (e.g. completion
  tokens are `0` with no HTTP error), treat tool calling as **not supported**
  until it stabilizes.

### Directives (structured output)

- Use `script/llm_directives_eval.rb` as the gate: if a model passes the default
  scenarios across the strategies you care about, it’s usually safe for UI IR.
- Some providers/models require workarounds (encoded in the eval catalogs and
  presets). Treat those presets as part of “model selection”, not as optional
  sugar.

### Multilingual / roleplay

- Always re-run eval with `OPENROUTER_LANGUAGE_POLICY_MATRIX=1` before declaring
  a model “stable”, because language policy amplifies the tendency to add extra
  natural-language noise during protocol turns.
- For roleplay, use `<lang code="...">...</lang>` spans when you need a
  character to speak in a different language than the user’s target language.
  Keep these tags out of the final UI by enabling the output tag transformer
  (`context[:output_tags]`).

## Reducing eval flakiness

Providers can occasionally return HTTP-200 with an empty `assistant_text`.
All eval scripts support:

- `OPENROUTER_EMPTY_RESPONSE_RETRY_COUNT` (default: `1`)

This retries the request once when the response is empty (but not an HTTP error)
to keep reports from being dominated by transient upstream issues.

## Keeping the model list current

The “stable” lists live in the `MODEL_CATALOG` blocks under:

- `script/llm_tool_call_eval.rb`
- `script/llm_directives_eval.rb`
- `script/llm_language_policy_eval.rb`

Keep them in sync when adding/removing models, and update this doc with any
model-specific caveats (tool calling quirks, directives mode limitations, etc.).
