# TODO: Local OpenAI-Compatible Providers (vLLM / llama.cpp)

We currently validate `TavernKit::VibeTavern` mostly against OpenRouter (and
OpenAI-compatible behavior as implemented by OpenRouter’s routing layer).

If we plan to run this stack in production against **local OpenAI-compatible**
servers, we should explicitly test (and document) compatibility with:

- vLLM
- llama.cpp

## Why this matters

Local servers often differ from OpenRouter/OpenAI in subtle but important ways:

- tool call response shape (`function_call` vs `tool_calls`, array vs object)
- `arguments` type (JSON string vs JSON object)
- tool-call turns with missing/empty `assistant.content`
- structured outputs (`response_format`) support or exact semantics
- streaming event shapes (if/when we enable streaming)

## Plan (deferred)

1) Add a local-provider eval preset (base_url/auth + model list) to
   `script/llm_vibe_tavern_eval.rb`.
2) Run a small smoke matrix first (TRIALS=1, a few scenarios/models), then expand.
3) If incompatibilities appear:
   - keep fixes **opt-in** via presets/transforms
   - avoid hardcoding provider quirks into the core runners
4) Update research docs with findings and recommended presets.

## Acceptance criteria

- Tool calling: at least one vLLM model and one llama.cpp model can complete the
  “tool” scenarios under an explicit preset without lowering guardrails.
- Directives: works at least in `json_object` or `prompt_only` mode (and clearly
  reports when `json_schema` is not supported).
- Any provider-specific behavior remains isolated to presets/transforms and has
  deterministic test coverage where feasible.
