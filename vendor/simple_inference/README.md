# SimpleInference

A lightweight, Fiber-friendly Ruby client for OpenAI-compatible LLM APIs. Works seamlessly with OpenAI, Azure OpenAI, 火山引擎 (Volcengine), DeepSeek, Groq, Together AI, and any other provider that implements the OpenAI API specification.

Designed for simplicity and compatibility – no heavy dependencies, just pure Ruby with `Net::HTTP`.

## Features

- 🔌 **Universal compatibility** – Works with any OpenAI-compatible API provider
- 🌊 **Streaming support** – Native SSE streaming for chat completions
- 🧵 **Fiber-friendly** – Compatible with Ruby 3 Fiber scheduler, works great with Falcon
- 🔧 **Flexible configuration** – Customizable API prefix for non-standard endpoints
- 🎯 **Simple interface** – Receive-an-Object / Return-an-Object style API
- 📦 **Zero runtime dependencies** – Uses only Ruby standard library

## Installation

Add to your Gemfile:

```ruby
gem "simple_inference"
```

Then run:

```bash
bundle install
```

## Quick Start

```ruby
require "simple_inference"

# Connect to OpenAI
client = SimpleInference::Client.new(
  base_url: "https://api.openai.com",
  api_key: ENV["OPENAI_API_KEY"]
)

result = client.chat(
  model: "gpt-4o-mini",
  messages: [{ "role" => "user", "content" => "Hello!" }]
)

puts result.content
p result.usage
```

## Protocols / Contract

SimpleInference exposes a small, OpenAI-shaped chat contract that upper layers
(like `TavernKit::VibeTavern`) can depend on.

### Required methods

#### `#chat_completions(**params) -> SimpleInference::Response`

- Request params follow the OpenAI Chat Completions shape (e.g. `model`,
  `messages`, `tools`, `response_format`, etc.).
- On success, `response.body` is a Hash (String keys) that contains an
  OpenAI-like payload:
  - `body["choices"][0]["message"]` (Hash)
  - `body["choices"][0]["finish_reason"]` (String/nil)
  - `body["usage"]` (Hash/nil)
- On non-2xx responses, it raises `SimpleInference::Errors::HTTPError` by
  default (`raise_on_error: true`), and the error exposes `#status`, `#body`,
  and `#raw_body`.

#### `#chat(model:, messages:, stream:, include_usage:, **opts, &on_delta) -> SimpleInference::OpenAI::ChatResult`

- Non-streaming: returns a `ChatResult` with `content`, `usage`, `finish_reason`,
  and `response`.
- Streaming: yields **String** deltas to the given block and returns the final
  accumulated `ChatResult`.

### Adding new protocols

New protocol implementations (Anthropic/Gemini/etc.) should translate
provider-native APIs into the OpenAI-like response body shape above, so app code
can keep a single parsing path.

## Configuration

### Options

| Option | Env Variable | Default | Description |
|--------|--------------|---------|-------------|
| `base_url` | `SIMPLE_INFERENCE_BASE_URL` | `http://localhost:8000` | API base URL |
| `api_key` | `SIMPLE_INFERENCE_API_KEY` | `nil` | API key (sent as `Authorization: Bearer <token>`) |
| `api_prefix` | `SIMPLE_INFERENCE_API_PREFIX` | `/v1` | API path prefix (e.g., `/v1`, empty string for some providers) |
| `timeout` | `SIMPLE_INFERENCE_TIMEOUT` | `nil` | Request timeout in seconds |
| `open_timeout` | `SIMPLE_INFERENCE_OPEN_TIMEOUT` | `nil` | Connection open timeout |
| `read_timeout` | `SIMPLE_INFERENCE_READ_TIMEOUT` | `nil` | Read timeout |
| `raise_on_error` | `SIMPLE_INFERENCE_RAISE_ON_ERROR` | `true` | Raise exceptions on HTTP errors |
| `headers` | – | `{}` | Additional headers to send with requests |
| `adapter` | – | `Default` | HTTP adapter (see [Adapters](#http-adapters)) |

Note: `base_url` must include a URL scheme (e.g. `https://api.openai.com`).

### Provider Examples

#### OpenAI

```ruby
client = SimpleInference::Client.new(
  base_url: "https://api.openai.com",
  api_key: ENV["OPENAI_API_KEY"]
)
```

#### 火山引擎 (Volcengine / ByteDance)

火山引擎的 API 路径不包含 `/v1` 前缀，需要设置 `api_prefix: ""`：

```ruby
client = SimpleInference::Client.new(
  base_url: "https://ark.cn-beijing.volces.com/api/v3",
  api_key: ENV["ARK_API_KEY"],
  api_prefix: ""  # 重要：火山引擎不使用 /v1 前缀
)

result = client.chat(
  model: "deepseek-v3-250324",
  messages: [
    { "role" => "system", "content" => "你是人工智能助手" },
    { "role" => "user", "content" => "你好" }
  ]
)

puts result.content
```

#### DeepSeek

```ruby
client = SimpleInference::Client.new(
  base_url: "https://api.deepseek.com",
  api_key: ENV["DEEPSEEK_API_KEY"]
)
```

#### Groq

```ruby
client = SimpleInference::Client.new(
  base_url: "https://api.groq.com/openai",
  api_key: ENV["GROQ_API_KEY"]
)
```

#### Together AI

```ruby
client = SimpleInference::Client.new(
  base_url: "https://api.together.xyz",
  api_key: ENV["TOGETHER_API_KEY"]
)
```

#### Local inference servers (Ollama, vLLM, etc.)

```ruby
# Ollama
client = SimpleInference::Client.new(
  base_url: "http://localhost:11434"
)

# vLLM
client = SimpleInference::Client.new(
  base_url: "http://localhost:8000"
)
```

#### Custom authentication header

Some providers use non-standard authentication headers:

```ruby
client = SimpleInference::Client.new(
  base_url: "https://my-service.example.com",
  api_prefix: "/v1",
  headers: {
    "x-api-key" => ENV["MY_SERVICE_KEY"]
  }
)
```

## API Methods

### Chat

```ruby
result = client.chat(
  model: "gpt-4o-mini",
  messages: [
    { "role" => "system", "content" => "You are a helpful assistant." },
    { "role" => "user", "content" => "Hello!" }
  ],
  temperature: 0.7,
  max_tokens: 1000
)

puts result.content
p result.usage
```

### Streaming Chat

```ruby
result = client.chat(
  model: "gpt-4o-mini",
  messages: [{ "role" => "user", "content" => "Tell me a story" }],
  stream: true,
  include_usage: true
) do |delta|
  print delta
end
puts

p result.usage
```

Low-level streaming (events) is also available, and can be used as an Enumerator:

```ruby
stream = client.chat_completions_stream(
  model: "gpt-4o-mini",
  messages: [{ "role" => "user", "content" => "Hello" }]
)

stream.each do |event|
  # process event
end
```

Or as an Enumerable of delta strings:

```ruby
stream = client.chat_stream(
  model: "gpt-4o-mini",
  messages: [{ "role" => "user", "content" => "Hello" }],
  include_usage: true
)

stream.each { |delta| print delta }
puts
p stream.result&.usage
```

### Embeddings

```ruby
response = client.embeddings(
  model: "text-embedding-3-small",
  input: "Hello, world!"
)

vector = response.body["data"][0]["embedding"]
```

### Rerank

```ruby
response = client.rerank(
  model: "bge-reranker-v2-m3",
  query: "What is machine learning?",
  documents: [
    "Machine learning is a subset of AI...",
    "The weather today is sunny...",
    "Deep learning uses neural networks..."
  ]
)
```

### Audio Transcription

```ruby
response = client.audio_transcriptions(
  model: "whisper-1",
  file: File.open("audio.mp3", "rb")
)

puts response.body["text"]
```

### Audio Translation

```ruby
response = client.audio_translations(
  model: "whisper-1",
  file: File.open("audio.mp3", "rb")
)
```

### List Models

```ruby
model_ids = client.models
```

### Health Check

```ruby
# Returns full response
response = client.health

# Returns boolean
if client.healthy?
  puts "Service is up!"
end
```

## Response Format

All HTTP methods return a `SimpleInference::Response` with:

```ruby
response.status   # Integer HTTP status code
response.headers  # Hash with downcased String keys
response.body     # Parsed JSON (Hash/Array), raw String, or nil (SSE success)
response.success? # true for 2xx
```

## Error Handling

By default, non-2xx responses raise exceptions:

```ruby
begin
  client.chat_completions(model: "invalid", messages: [])
rescue SimpleInference::Errors::HTTPError => e
  puts "HTTP #{e.status}: #{e.message}"
  p e.body      # parsed body (Hash/Array/String)
  puts e.raw_body # raw response body string (if available)
end
```

Other exception types:

- `SimpleInference::Errors::TimeoutError` – Request timed out
- `SimpleInference::Errors::ConnectionError` – Network error
- `SimpleInference::Errors::DecodeError` – JSON parsing failed
- `SimpleInference::Errors::ConfigurationError` – Invalid configuration

To handle errors manually:

```ruby
client = SimpleInference::Client.new(
  base_url: "https://api.openai.com",
  api_key: ENV["OPENAI_API_KEY"],
  raise_on_error: false
)

response = client.chat_completions(model: "gpt-4o-mini", messages: [...])

if response.success?
  # success
else
  puts "Error: #{response.status} - #{response.body}"
end
```

## HTTP Adapters

### Default (Net::HTTP)

The default adapter uses Ruby's built-in `Net::HTTP`. It's thread-safe and compatible with Ruby 3 Fiber scheduler.

### HTTPX Adapter

For better performance or async environments, use the optional HTTPX adapter:

```ruby
# Gemfile
gem "httpx"
```

```ruby
adapter = SimpleInference::HTTPAdapters::HTTPX.new(timeout: 30.0)

client = SimpleInference::Client.new(
  base_url: "https://api.openai.com",
  api_key: ENV["OPENAI_API_KEY"],
  adapter: adapter
)
```

### Custom Adapter

Implement your own adapter by subclassing `SimpleInference::HTTPAdapter`:

```ruby
class MyAdapter < SimpleInference::HTTPAdapter
  def call(request)
    # request keys: :method, :url, :headers, :body, :timeout, :open_timeout, :read_timeout
    # Must return: { status: Integer, headers: Hash, body: String }
  end

  def call_stream(request, &block)
    # For streaming support (optional)
    # Yield raw chunks to block for SSE responses
  end
end
```

## Rails Integration

Create an initializer `config/initializers/simple_inference.rb`:

```ruby
INFERENCE_CLIENT = SimpleInference::Client.new(
  base_url: ENV.fetch("INFERENCE_BASE_URL", "https://api.openai.com"),
  api_key: ENV["INFERENCE_API_KEY"]
)
```

Use in controllers:

```ruby
class ChatsController < ApplicationController
  def create
    response = INFERENCE_CLIENT.chat_completions(
      model: "gpt-4o-mini",
      messages: [{ "role" => "user", "content" => params[:prompt] }]
    )

    render json: response.body
  end
end
```

Use in background jobs:

```ruby
class EmbedJob < ApplicationJob
  def perform(text)
    response = INFERENCE_CLIENT.embeddings(
      model: "text-embedding-3-small",
      input: text
    )

    vector = response.body["data"][0]["embedding"]
    # Store vector...
  end
end
```

## Thread Safety

The client is thread-safe:

- No global mutable state
- Per-client configuration only
- Each request uses its own HTTP connection

## License

MIT License. See [LICENSE](LICENSE.txt) for details.
