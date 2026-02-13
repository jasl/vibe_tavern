# Language Policy (Native Multilingual Output)

VibeTavern supports “native multilingual” output via a prompt-building step:

- `TavernKit::VibeTavern::PromptBuilder::Steps::LanguagePolicy`

Goal:
- make the assistant respond in a target language (app-configurable)
- preserve protocol correctness for tool calling / directives
- preserve “verbatim zones” (code/macros/tags/URLs) without introducing an
  app-level safety policy layer

This is a **generation-time constraint** (prompt policy), not a translator.

## Contract (P0)

Given `context[:language_policy][:target_lang]`:

1) Assistant natural language is in `target_lang`
   - includes the final assistant answer after tool calls complete
   - includes `assistant_text` in a directives envelope
2) Verbatim zones are not translated/rewritten
3) Protocol is preserved
   - tool names / ids / JSON keys are never translated
   - directive `type` strings are canonical (app-defined)
4) When goals conflict, protocol reliability wins
   - language policy must not reduce tool-call or directives success rate

## Configuration surface

Primary config lives in the request-scoped context snapshot:

- `context[:language_policy]`
  - `enabled` (Boolean)
  - `target_lang` (String; canonicalized + allowlisted)
  - `style_hint` (String; optional)
  - `special_tags` (Array<String>; optional)
  - `policy_text_builder` (callable; optional)

The app typically injects `target_lang` from a user preference/settings model,
instead of trying to infer it from chat text.

### Supported language codes

Language codes are strict and allowlisted:

- `TavernKit::VibeTavern::LanguagePolicy::SUPPORTED_TARGET_LANGS`

Canonicalization + aliases live in:

- `TavernKit::VibeTavern::LanguagePolicy.canonical_target_lang`

If `target_lang` is not supported, the step disables itself for that run and
emits a warning into the plan (no guessing).

## Implementation notes

### Pipeline insertion point

The step injects a short system policy block with slot `:language_policy`:

- inserted before the user message block (when present), otherwise before the
  trailing user/tool “tail” blocks
- keeps the last message as user/tool when possible (better chat semantics)

See:
- `lib/tavern_kit/vibe_tavern/prompt_builder/steps/language_policy.rb`

### Default policy text

The default policy text is built by:

- `Steps::LanguagePolicy::DEFAULT_POLICY_TEXT_BUILDER`

It includes:
- the target language + optional style hint
- a verbatim preservation rule set
- “tool-call turns must be tool calls only” guidance

You can override the builder via `policy_text_builder` (a callable).
Prefer passing callables via `RunnerConfig.build(step_options: ...)` so your
context stays serializable.

## Verbatim zones (must-preserve)

LanguagePolicy’s prompt guidance treats these as “verbatim”:

- fenced code blocks (```...```)
- inline code (`...`)
- Liquid macro syntax (`{{ }}` / `{% %}`)
- HTML/XML-ish tags (`<...>`)
- URLs / Markdown links (do not rewrite or shorten)
- app-defined “special tags” (when provided via `special_tags`)
- protocol surfaces:
  - tool call names / ids / JSON keys / structured args
  - directives envelope keys and directive type strings

Note: some of these are also protected by **runner-level invariants** (not just
prompt guidance). For example, ToolLoopRunner forces assistant content to `""`
when tool calls are present, which prevents “language policy bleed” into tool
call turns.

## Related: OutputTags post-processing (optional)

Some XML-ish tags (e.g. `<lang code="...">...</lang>`) are useful as prompt
control markers but shouldn’t necessarily be shown to end users.

VibeTavern supports an optional deterministic post-pass via `context[:output_tags]`
normalized by `RunnerConfig`:

- `TavernKit::VibeTavern::OutputTags.transform(text, config: runner_config.output_tags)`

This is applied by protocol runners to:
- tool-loop final assistant text
- directives `assistant_text`

## Evaluation harnesses

Networked (optional):
- `script/eval/llm_language_policy_eval.rb` (chat-only focus: verbatim zones, tags, drift)
- `script/eval/llm_vibe_tavern_eval.rb` (full run matrix, includes language policy dimension)

Deterministic coverage:
- pipeline + step behavior is pinned by unit tests under `test/`

## Future work (not implemented)

- Drift detection + optional rewrite fallback for **non-streaming** outputs.
- Hit-based glossary / “no translate list” injection to stabilize terminology.
- App-level UX for per-turn language overrides (`allow_language_switch`).
