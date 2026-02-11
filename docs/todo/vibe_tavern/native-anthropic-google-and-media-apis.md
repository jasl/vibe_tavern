# TODO: Native Anthropic + Google APIs (Text/Tools/Directives) + Media Generation

We currently run `TavernKit::VibeTavern` against **OpenAI-compatible** HTTP APIs
via `vendor/simple_inference` (`SimpleInference::Protocols::OpenAICompatible`).
That covers OpenAI/OpenRouter/vLLM/llama.cpp-style transports, but blocks:

- native Anthropic (Messages API)
- native Google (Gemini / Generative Language, and/or Vertex AI)
- native media generation (OpenAI images + Sora; Google image generation)

This doc assesses the current design and proposes a plan to add those providers
without making `lib/tavern_kit/vibe_tavern/prompt_runner.rb` (or the tool loop)
provider-specific.

## Constraints (must stay true)

- `PromptRunner` remains the **single request boundary** for text runs.
  - Call sites (tool loop, directives runner) should not grow per-provider
    branching.
- Provider quirks stay **opt-in** via capabilities + presets/transforms.
- Deterministic tests should cover the protocol mapping (no “best effort”
  implicit behavior hidden in the app layer).
- Media generation is **not** routed through `PromptRunner` (separate API
  surface), but should reuse the same transport/client patterns.

## Current design assessment

### What’s already good (seams we can use)

- `RunnerConfig` + `Capabilities` + `Preflight` centralize invariants:
  - tools vs `response_format` mutual exclusion
  - streaming restrictions
  - capability gating for tools/structured outputs/streaming
- Tool calling and directives already isolate provider quirks into:
  - presets: `lib/tavern_kit/vibe_tavern/*/presets.rb`
  - transforms: `lib/tavern_kit/vibe_tavern/tool_calling/*_transforms.rb`
- `vendor/simple_inference` already has a protocol namespace:
  - `SimpleInference::Protocols::*`
  - default `SimpleInference::Client < Protocols::OpenAICompatible`
- `vendor/tavern_kit` already has prompt dialect converters for:
  - `:anthropic`
  - `:google`
  (even though transport is still OpenAI-compatible today)

### Where we are coupled today (why native APIs don’t “just work”)

`PromptRunner` currently assumes an OpenAI chat-completions wire protocol:

- request shape: `{ model:, messages:, ...openai_fields }`
- transport call: `client.chat_completions(**request)`
- response shape: `choices[0].message` + `usage` + `finish_reason`
- tool calling: OpenAI `tools/tool_choice` + `tool_calls` + `role: "tool"` history
- structured outputs: OpenAI `response_format` (`json_object` / `json_schema`)

Native Anthropic/Gemini APIs differ in:

- endpoint + auth headers
- “system” handling (separate field vs role messages)
- tool schema format + tool tracing message format
- structured output knobs (Gemini schema fields vs OpenAI `response_format`)
- streaming event types

## Recommendation (smallest refactor that keeps PromptRunner friendly)

Keep **OpenAI chat-completions** as VibeTavern’s *canonical* request/response
shape, and implement native providers as **protocol adapters in SimpleInference**
that translate:

1) OpenAI-shaped request → native provider request
2) native provider response → OpenAI-shaped response body

This keeps:

- `PromptRunner` unchanged (still reads `choices[0].message`)
- `ToolLoopRunner` unchanged (still parses `tool_calls` and appends `role: "tool"`)
- transforms/presets still applicable (they operate on OpenAI-shaped messages)

Alternative (not recommended for first pass):

- Refactor VibeTavern to speak native wire formats directly (would require
  touching PromptRunner + tool loop + schema handling + tests).

## Difficulty / risk (rough)

- Chat-only (no tools, no `response_format`): **low–medium**
- Tool calling parity (multi-turn): **medium–high**
- Structured directives (`response_format` mapping): **medium** (Gemini) / **high** (Anthropic; likely prompt-only)
- Streaming parity: **medium–high**
- Media generation (images/video): **high uncertainty** (API variance + async flows)

## Plan (deferred but scoped)

### Phase 0: Lock the adapter contract (design + tests-first)

- Define the canonical interface expected by VibeTavern runners:
  - `#chat_completions(**openai_params) -> SimpleInference::Response`
  - `#chat(model:, messages:, stream:, include_usage:, **opts) -> SimpleInference::OpenAI::ChatResult`
  - raises `SimpleInference::Errors::HTTPError` consistently on HTTP failures
- Define the canonical OpenAI-shaped subset we commit to supporting across adapters:
  - `messages` role semantics + tool tracing fields
  - `tools`, `tool_choice`, `parallel_tool_calls`
  - `response_format` as best-effort (capability-gated)
- Add “normalization spec” test vectors:
  - OpenAI request → expected provider JSON + headers
  - provider response → expected OpenAI-shaped body (`choices[0].message`, `usage`)

### Phase 1: Add native text protocols to SimpleInference (chat-only)

Add protocols alongside `OpenAICompatible`:

- `SimpleInference::Protocols::Anthropic`
  - target: Anthropic Messages API
  - map OpenAI messages:
    - merge `role: "system"` into a provider `system` string
    - map user/assistant messages to Anthropic content blocks
  - normalize response blocks back into OpenAI `message.content`
  - normalize usage and finish reason
- `SimpleInference::Protocols::GoogleGemini`
  - target: Google Generative Language (Gemini) API-key surface (first pass)
  - map OpenAI messages → `{ system_instruction, contents }`
  - normalize candidate parts back into OpenAI `message.content`
  - normalize usage where available

Construction/back-compat options:

- Option A: `SimpleInference::Client.for(protocol: :anthropic, ...)`
- Option B: instantiate protocol classes directly and pass to PromptRunner:
  `PromptRunner.new(client: SimpleInference::Protocols::Anthropic.new(...))`

Tests:

- Fake-adapter unit tests per protocol (no network) that assert:
  - URL/path
  - required headers
  - request JSON shape
  - normalized OpenAI-like response body.

### Phase 2: Tool calling parity (ToolLoopRunner unchanged)

Implement tool mapping in protocol adapters (keep `ToolRegistry#openai_tools` as canonical):

- Tool definitions:
  - OpenAI tool schema → Anthropic `tools` (`name`, `description`, `input_schema`)
  - OpenAI tool schema → Gemini function declarations (verify exact fields)
- Tool calls in responses:
  - Anthropic `tool_use` blocks → OpenAI `tool_calls`
  - Gemini functionCall parts → OpenAI `tool_calls`
- Tool results in subsequent requests:
  - OpenAI `role: "tool"` message + `tool_call_id` → provider-specific tool result message
- Tool IDs:
  - preserve IDs when provider returns them
  - synthesize stable IDs when provider lacks them (must round-trip in history)

Tests:

- Minimal 2-turn tool loop integration test per provider with fake adapters:
  - assistant emits tool call
  - tool result is appended
  - second request includes correct tool tracing payload

### Phase 3: Structured directives support (capabilities + best-effort mapping)

Update `lib/tavern_kit/vibe_tavern/capabilities_registry.rb` to include explicit
provider defaults:

- `anthropic`: start conservative:
  - `supports_response_format_json_object: false`
  - `supports_response_format_json_schema: false`
  - directives runner should skip structured modes and use `prompt_only`
- `google`: enable structured outputs only after mapping exists:
  - map OpenAI `response_format` to Gemini schema fields (verify API):
    - `json_object` → JSON MIME type (or equivalent)
    - `json_schema` → response schema (if supported)

Update directives/tool-calling presets as needed to keep provider-specific
request knobs out of VibeTavern core.

Tests:

- Directives::Runner fallback behavior with:
  - capabilities forcing mode skipping (no HTTP attempt)
  - provider returning schema/JSON errors (retry + mode downgrade)

### Phase 4: Streaming parity (PromptRunner#perform_stream contract preserved)

Implement `#chat(..., stream: true)` per protocol:

- Anthropic streaming events → yield text deltas + collect final usage
- Gemini streaming endpoint/events → yield text deltas + collect final usage

Keep existing invariants:

- no streaming for tool calling turns
- no streaming for `response_format` requests

Tests:

- streaming event fixtures that verify:
  - deltas yielded in order
  - final `ChatResult.content`, `finish_reason`, `usage` are populated

### Phase 5: Media generation (OpenAI + Google)

Treat media generation as a separate surface (not `PromptRunner`):

- Add a `SimpleInference::Media` (or protocol methods) namespace:
  - `images.generate(...)`
  - `videos.generate(...)` (for Sora-like flows)
- OpenAI:
  - images endpoint(s) (prompt → base64/URL)
  - Sora/video generation is likely async: plan for create → poll → download
- Google:
  - decide target surface:
    - Generative Language (Gemini) image outputs, or
    - Vertex AI Imagen (likely) for image generation
  - “Nano banana pro” needs concrete mapping:
    - model ID, endpoint, auth mode (API key vs OAuth)

App-layer integration (Rails):

- wrapper service that:
  - persists outputs to ActiveStorage
  - audit logs requests + model IDs + sizes
  - enforces quotas/limits

### Phase 6: Eval harness + docs

- Extend existing eval scripts to support native providers (smoke matrix first):
  - `script/llm_tool_call_eval.rb`
  - `script/llm_directives_eval.rb`
- Document:
  - credential configuration for Anthropic + Google
  - known limitations per provider (tools/schema/streaming)
  - recommended `RunnerConfig` presets per provider/model

## Acceptance criteria

Text (non-stream):

- `PromptRunner#perform` works end-to-end against:
  - 1 Anthropic model via native API
  - 1 Gemini model via native API
- Errors surface as `SimpleInference::Errors::HTTPError` with `status` + body.

Tools:

- `ToolLoopRunner` completes at least one tool-using scenario per provider with:
  - stable tool_call IDs
  - correct tool result tracing across turns

Directives:

- `Directives::Runner` completes at least one run per provider:
  - Gemini: structured mode or clear fallback
  - Anthropic: prompt-only mode, with structured modes skipped via capabilities

Streaming:

- `PromptRunner#perform_stream` yields deltas and returns final content + usage
  for both providers.

Media:

- One OpenAI image generation call and one Google image generation call can
  produce and persist an image output with deterministic metadata.

## Open questions (need answers before Phase 5)

- What exactly is “Nano banana pro” (provider product, model ID, endpoint, auth)?
- Which Google surface do we want as the long-term default:
  - `generativelanguage.googleapis.com` (API key) vs Vertex AI (OAuth)?
- Do we need embeddings/rerank parity now, or only chat + tools + directives?

