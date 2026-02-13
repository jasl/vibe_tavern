# LLM Configuration (DB-backed)

This Rails app stores LLM configuration in the database using a 3-level model:

- `LLMProvider`: provider connection settings (endpoint + headers + encrypted API key)
- `LLMModel`: model entries (enabled flag + capabilities **expanded into columns**)
- `LLMPreset`: optional sampling/request overrides (e.g. temperature/top_p)

The goal is to keep `TavernKit::VibeTavern` configuration **request-scoped** while
still letting the app persist defaults and a model catalog.

## Data model

### `LLMProvider`

File: `app/models/llm_provider.rb`

- Connection fields: `base_url`, `api_prefix`, `headers`
- API protocol: `api_format` (currently only `"openai"` is supported)
- Secret: `api_key` (`encrypts :api_key`)
- Provider-level defaults: `llm_options_defaults` (JSON; reserved keys rejected)

It also provides bulk toggles:

- `LLMProvider#enable_all!` / `LLMProvider#disable_all!` (toggles `LLMModel.enabled`)

### `LLMModel`

File: `app/models/llm_model.rb`

- Identity: `llm_provider_id` + `model` (unique per provider)
- Display name: `name` (required)
- Optional quick locator: `key` (globally unique when present; normalized to lowercase)
- State: `enabled` (selection availability) and `connection_tested_at` (only set on successful tests)
- Human notes: `comment`
- Capabilities (all boolean columns; DB is the source of truth):
  - `supports_tool_calling`
  - `supports_response_format_json_object`
  - `supports_response_format_json_schema`
  - `supports_streaming`
  - `supports_parallel_tool_calls`

### `LLMPreset`

File: `app/models/llm_preset.rb`

- Belongs to a model
- Optional `key` (unique per model when present; normalized to lowercase)
- `llm_options_overrides` (JSON; reserved keys rejected)
- Human notes: `comment`

## VibeTavern integration

### Build a `SimpleInference::Client`

`LLMProvider#build_simple_inference_client` wires the persisted connection
settings into `SimpleInference::Client`.

### Build a `TavernKit::VibeTavern::RunnerConfig`

`LLMModel#build_runner_config(preset: ...)` merges:

1) provider-level defaults (`LLMProvider#llm_options_defaults`)
2) preset overrides (`LLMPreset#llm_options_overrides`)

…and passes them into `TavernKit::VibeTavern::RunnerConfig.build(...)` together
with `capabilities_overrides` built from the `supports_*` columns.

Important: `build_runner_config` currently calls `RunnerConfig.build` with
`provider: llm_provider.api_format` (currently `"openai"`). This means OpenRouter-specific provider
presets in VibeTavern (e.g. routing/request overrides) are not applied
automatically; if you need them, pass them explicitly via `context`.

## Connection testing

Service: `app/services/test_llm_model_connection.rb`

- Success: sets `LLMModel.connection_tested_at = Time.current`
- Failure (any error): clears `LLMModel.connection_tested_at = nil`

## Run a prompt

Service: `app/services/llm/run_chat.rb`

`LLM::RunChat` is the app-level, end-to-end entrypoint that wires:

- DB config (`LLMProvider` / `LLMModel` / `LLMPreset`)
- `TavernKit::VibeTavern::RunnerConfig`
- `TavernKit::VibeTavern::PromptRunner`
- `SimpleInference` transport client

Example:

```ruby
llm_model = LLMModel.find_by!(key: "my-model") # or any other lookup

result =
  LLM::RunChat.call(
    llm_model: llm_model,
    user_text: "Hello!",
    context: { "language_policy" => { "enabled" => true, "target_lang" => "zh-CN" } },
  )

if result.success?
  prompt_result = result.value.fetch(:prompt_result)
  prompt_result.assistant_message.fetch("content", "")
else
  raise result.errors.join(", ")
end
```

Notes:

- When `preset:` / `preset_key:` is not provided, it auto-uses the model preset with `key: "default"` when present.
- `LLMModel.enabled=false` blocks runs unless `allow_disabled: true` is passed explicitly.

## Token budget / Prompt length limits

To avoid provider-side “context length exceeded” errors, the app can enforce a
fail-fast prompt budget at build time (before sending the request).

The budget is configured in the DB:

- `LLMModel.context_window_tokens` (Integer; **0 = unlimited**)
- `LLMProvider.message_overhead_tokens` (Integer; per-message overhead; default 0)
- `LLMModel.message_overhead_tokens` (Integer, nullable; when `nil`, inherits provider overhead; `0` is a valid override)

Budget enforcement happens in the VibeTavern pipeline `max_tokens` step. When a
budget is configured (`context_window_tokens > 0`) it raises `TavernKit::MaxTokensExceededError`.
`LLM::RunChat` converts that into `Result.failure(code: "PROMPT_TOO_LONG", ...)` with budget details.

`reserve_tokens` behavior:

- There is no DB column for output reservation.
- The max-tokens step dynamically reserves tokens from the request option
  `llm_options[:max_tokens]` (when present). If you don’t set `max_tokens`,
  the reserve defaults to `0`.

Limitations (known):

- The estimate is based on **messages content + per-message overhead** (message metadata is not counted today).
- Tool definition payload (`tools:` JSON Schemas) is not part of this estimate and can still hit provider-side limits.

## Mock (Local) provider (dev/test)

This app exposes a tiny OpenAI-compatible mock LLM API (development/test only):

- `GET /mock_llm/v1/models`
- `POST /mock_llm/v1/chat/completions` (supports `stream=true` SSE)

Seeds create a convenience provider + model:

- `LLMProvider(name: "Mock (Local)")` with `base_url` from `MOCK_LLM_BASE_URL` (default `http://localhost:3000`)
- `LLMModel(key: "mock", model: "mock")` enabled, streaming-capable

To use it:

```ruby
llm_model = LLMModel.find_by!(key: "mock")
result = LLM::RunChat.call(llm_model: llm_model, user_text: "Hello!")
```

Limitations:

- No tool calling
- No `response_format`

Streaming:

- `MOCK_LLM_STREAM_DELAY` controls the per-chunk delay (default `0.02`, forced to `0.0` in test)

## Seeds

Seeds live under `db/seeds/` and are loaded via `db/seeds.rb`.

File: `db/seeds/llm.rb`

- Seeds a set of providers (OpenRouter + legacy endpoints)
- Seeds the OpenRouter eval-catalog models (17 entries) as `LLMModel(enabled: true)`
- Seeds one `LLMPreset(key: "default")` per OpenRouter model using the
  “production recommended” sampling params (duplicated in the seeds file;
  no `script/*` requires)
- Seeds are create-only: re-running does not overwrite user edits.
