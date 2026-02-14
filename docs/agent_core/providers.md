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
- Tool calling: parses OpenAI `tool_calls` / `function_call` into `AgentCore::ToolCall` (arguments are deep-symbolized).
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

