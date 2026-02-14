# Providers (AgentCore)

AgentCore treats the LLM vendor/API client as an **adapter** (Provider). The core
engine (`PromptRunner`) only depends on a small contract:

- `Provider#chat(messages:, model:, tools: nil, stream: false, **options)`
  - non-streaming: returns `AgentCore::Resources::Provider::Response`
  - streaming: returns an `Enumerator` that yields `AgentCore::StreamEvent` objects

The provider is responsible for:

- serializing `AgentCore::Message` into the upstream API shape
- converting tool definitions (`Registry#definitions`) into the upstream tool schema
- parsing upstream responses into `AgentCore::Message` (+ tool calls + usage)

## Optional default: SimpleInference (OpenAI-compatible)

AgentCore ships an **optional** provider adapter based on `simple_inference`.

- Soft dependency: AgentCore does not require `simple_inference` by default.
- Lazy load: you must require the adapter file explicitly.

### Usage

```ruby
require "agent_core"
require "agent_core/resources/provider/simple_inference_provider"

provider = AgentCore::Resources::Provider::SimpleInferenceProvider.new(
  base_url: "https://api.openai.com",
  api_key: ENV["OPENAI_API_KEY"],
)
```

Or inject your own `SimpleInference::Client`:

```ruby
client = SimpleInference::Client.new(base_url: "...", api_key: "...")
provider = AgentCore::Resources::Provider::SimpleInferenceProvider.new(client: client)
```

### Notes

- Tools: accepts AgentCore “generic” tool definitions (`{ name:, description:, parameters: }`) and converts them to OpenAI `tools: [{ type: "function", function: ... }]`.
- Tool calling: parses OpenAI `tool_calls` / `function_call` into `AgentCore::ToolCall` (arguments are deep-stringified; keys are Strings).
- Streaming: consumes OpenAI-style SSE chunks, emits `StreamEvent::TextDelta`, `ToolCall*` events, then `MessageComplete` + `Done`.
- Multimodal: images are mapped to OpenAI `image_url` parts; documents/audio are stringified placeholders (provider-neutral fallback).

### HTTP client (httpx)

`simple_inference` defaults to Net::HTTP. If you prefer HTTPX (fiber-friendly),
configure SimpleInference with the HTTPX adapter in your app:

```ruby
client = SimpleInference::Client.new(
  base_url: "...",
  api_key: "...",
  adapter: SimpleInference::HTTPAdapters::HTTPX.new(timeout: 60),
)
```

### Built-in reliability shims (AgentCore)

These behaviors are implemented in AgentCore (provider adapter + runner) to keep
the tool loop stable across imperfect model/tool outputs:

- Default `parallel_tool_calls: false` when tools are present (unless explicitly set).
- Accepts OpenAI `tool_calls` as Array or Hash, and supports legacy `function_call`.
- Tool call arguments are parsed defensively (JSON object only; supports fenced
  JSON blocks; size-capped via `AgentCore::Utils::DEFAULT_MAX_TOOL_ARGS_BYTES`
  (default 200KB) in the provider adapter). Invalid/too-large arguments are
  recorded as `ToolCall#arguments_parse_error` and will **not** be executed.
  Custom providers should enforce a similar cap when parsing `tool_calls[].arguments`
  (or reuse `Utils.parse_tool_arguments`).
- Tool call IDs are normalized (blank/duplicate IDs rewritten as `tc_#` and
  de-duped with `__2`, `__3`, … suffixes) to keep tool results consistent.
- Tool schema is normalized for compatibility (omits `required: []` in JSON schema).
- Tool results are size-limited (`max_tool_output_bytes`, default 200KB). Oversized
  text is truncated with a `"[truncated]"` marker; oversized multimodal outputs
  are replaced by a text message.
- Invalid multimodal tool output does not crash the run; it falls back to a text
  error message.
- Optional “fix empty final”: if the model returns an empty final assistant
  message after tool use, the runner adds a user message
  (`"Please provide your final answer."`) and retries once (optionally disabling
  tools on the retry).
- Optional per-turn cap: `max_tool_calls_per_turn:` limits tool calls executed
  in a single turn; ignored tool calls are recorded and skipped.

## App-side provider/model workarounds (keep out of AgentCore core)

Some reliability hacks and provider/model compatibility shims are **deliberately
kept out of AgentCore core** (`PromptRunner`, `Message`, `ToolCall`, etc.) because
they:

- depend on non-standard fields (vendor extensions)
- are strongly coupled to a specific provider/model route
- increase maintenance burden and risk surprising defaults for downstream apps

Recommended place for these: **app-layer provider adapters/wrappers** (e.g.
subclassing or wrapping `SimpleInferenceProvider`, or injecting request options).

Below is a checklist of common app-side workarounds (with TavernKit references)
to help you “fill the gaps” when integrating a real provider.

### 1) Non-standard request overrides (OpenRouter routing knobs)

- What: `route`, `transforms`, `provider: { only/order/ignore }`, etc.
- Where: app layer via `SimpleInferenceProvider` `request_defaults:` or per-call
  `Provider#chat(**options)` overrides.
- Reference: `lib/tavern_kit/vibe_tavern/tool_calling/presets.rb` (`openrouter_routing`,
  `openrouter_tool_calling`).

### 2) Non-standard outbound message fields (model quirks)

These are vendor/model specific extension fields; keep them opt-in.

- DeepSeek / “reasoner” models: when an assistant message contains `tool_calls`,
  some routes require a dummy `reasoning_content: ""`.
  - Where: app layer provider wrapper/subclass; inject during message serialization.
  - Reference: `lib/tavern_kit/vibe_tavern/transforms/message_transforms.rb`
    (`assistant_tool_calls_reasoning_content_empty_if_missing`).
- Gemini routes: tool call tracing may require a `signature` field (or a
  placeholder that skips validation).
  - Where: app layer provider wrapper/subclass; inject during message serialization.
  - Reference: `lib/tavern_kit/vibe_tavern/transforms/message_transforms.rb`
    (`assistant_tool_calls_signature_skip_validator_if_missing`).

### 3) Text-tag tool-call fallback (opt-in only)

- What: some weaker models emit textual `<tool_call>...</tool_call>` tags instead
  of structured `tool_calls`.
- Recommendation: keep this **disabled by default**; enable only for specific
  models/routes.
- Reference: `lib/tavern_kit/vibe_tavern/transforms/response_transforms.rb`
  (`assistant_content_tool_call_tags_to_tool_calls`).

### 4) Tool schema shims driven by provider strictness (opt-in)

- What: schema tweaks like stripping `function.description` because some strict
  OpenAI-compatible backends reject it.
- Recommendation: make these app-side transforms/presets, not core defaults.
- Reference: `lib/tavern_kit/vibe_tavern/tool_calling/tool_transforms.rb`
  (`openai_tools_strip_function_descriptions`).
