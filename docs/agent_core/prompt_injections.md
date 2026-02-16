# AgentCore prompt injections

AgentCore supports an optional **prompt injections** subsystem for injecting
text resources into the prompt in a consistent, configurable way.

This is designed to cover:

- OpenClaw-style “context files” injection (SOUL/MEMORY/etc.) into `system_prompt`
- Codex-style `<user_instructions>` injection into the message preamble
- App-provided injection (load from DB/cache/etc. outside AgentCore)

## Targets

Each injection is an `Item` with a `target`:

- `:system_section`
  - Appended to the end of `system_prompt` as an ordered “section”.
  - Supports optional variable substitution per-item.
- `:preamble_message`
  - Inserted into `messages` **before** chat history (and before the current user message).
  - Only supports `role: :user` or `role: :assistant` (no `:system`).

## Prompt modes

AgentCore supports two prompt modes:

- `:full` (default)
- `:minimal`

Each item can declare `prompt_modes: [:full, :minimal]`. When the app sets
`ExecutionContext.attributes[:prompt_mode] = :minimal`, full-only injections
are skipped.

## Truncation / budgets

Built-in sources apply a default truncation strategy:

- **Head + Marker + Tail** (OpenClaw-like), preserving UTF-8 validity.

Budgets exist at multiple levels depending on the source:

- per-file `max_bytes`
- per-source `total_max_bytes` / `max_total_bytes`
- per-entry `max_bytes` (TextStore / Provided items)

## Built-in sources

Configure sources in agent config v1:

```ruby
{
  version: 1,
  # ...
  prompt_injections: {
    sources: [
      # source specs...
    ],
  },
}
```

### `file_set` (OpenClaw-style)

Inject a set of files (relative to a runtime root directory) into `system_prompt`.

Source spec:

- `type: "file_set"`
- `section_header` (default: `"Project Context"`)
- `files: [{ path:, title:, max_bytes:, prompt_modes: }, ...]`
- `total_max_bytes` (optional)
- `root_key` (optional): which `ExecutionContext.attributes[...]` key holds the root path
  - default lookup order: `:workspace_dir`, then `:cwd`

Example:

```ruby
config[:prompt_injections][:sources] = [
  {
    type: "file_set",
    section_header: "Project Context",
    total_max_bytes: 30_000,
    files: [
      { path: "SOUL.md", max_bytes: 10_000, prompt_modes: [:full, :minimal] },
      { path: "MEMORY.md", max_bytes: 10_000, prompt_modes: [:full] },
    ],
  },
]
```

At runtime, pass `workspace_dir` (or `cwd`) into context:

```ruby
ctx = AgentCore::ExecutionContext.from(workspace_dir: Dir.pwd)
agent.chat("hi", context: ctx)
```

### `repo_docs` (Codex-style layered docs)

Find a repo root by walking up from `cwd` until `.git` exists (file or directory),
then load docs from `repo_root → cwd` directory layers.

This emits **one** `preamble_message(role: :user)` by default, wrapped as:

```text
<user_instructions>
...
</user_instructions>
```

Source spec:

- `type: "repo_docs"`
- `filenames` (default: `["AGENTS.md"]`)
- `max_total_bytes` (optional; applied to the body before wrapping)
- `wrapper_template` (optional; default shown above)

Example:

```ruby
config[:prompt_injections][:sources] = [
  {
    type: "repo_docs",
    filenames: ["AGENTS.md", "TOOLS.md"],
    max_total_bytes: 30_000,
    wrapper_template: "<user_instructions>\n{{content}}\n</user_instructions>",
  },
]
```

At runtime, pass `cwd`:

```ruby
ctx = AgentCore::ExecutionContext.from(cwd: Dir.pwd)
agent.chat("hi", context: ctx)
```

### `provided` (app loads items per call)

This source reads pre-built items from `ExecutionContext.attributes` (default key: `:prompt_injections`).

Source spec:

- `type: "provided"`
- `context_key` (optional)

Runtime usage:

```ruby
ctx =
  AgentCore::ExecutionContext.from(
    prompt_mode: :minimal,
    prompt_injections: [
      { target: :preamble_message, role: :user, content: "...", order: 10 },
      { target: :system_section, content: "...", order: 300 },
    ],
  )

agent.chat("hi", context: ctx)
```

This is the most convenient integration for:

- DB-backed instructions / policies
- A/B experiments
- tests (inject deterministic fixtures without touching the filesystem)

### `text_store` / `text_store_entries` (app provides a TextStore adapter)

This source reads text blobs from an app-provided adapter:

- `fetch(key:) -> String|nil`

Use this when the app wants AgentCore to do the per-prompt assembly, but the app
still owns persistence (DB/files/cache).

Source spec:

- `type: "text_store"` (alias: `"text_store_entries"`)
- `entries: [{ key:, target:, role:, order:, wrapper:, max_bytes:, prompt_modes: }, ...]`

Example config:

```ruby
config[:prompt_injections][:sources] = [
  {
    type: "text_store",
    entries: [
      {
        key: "project:soul",
        target: :system_section,
        order: 300,
        max_bytes: 10_000,
      },
      {
        key: "codex:user_instructions",
        target: :preamble_message,
        role: :user,
        order: 10,
        wrapper: "<user_instructions>\n{{content}}\n</user_instructions>",
        max_bytes: 30_000,
      },
    ],
  },
]
```

At runtime, pass the adapter into `Agent.from_config`:

```ruby
store = MyPromptTextStore.new

agent =
  AgentCore::Agent.from_config(
    config,
    provider: provider,
    prompt_injection_text_store: store,
  )
```

For tests, use `InMemory`:

```ruby
store =
  AgentCore::Resources::PromptInjections::TextStore::InMemory.new(
    "project:soul" => "Hello",
  )
```

## Notes

- Do not use `role: :system` for preamble messages. The runner applies the
  system prompt separately and may overwrite system messages in the messages array.
- Prompt injections are deliberately **storage-agnostic**: the app owns IO and persistence.

