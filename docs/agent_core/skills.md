# Skills (AgentCore vNext)

AgentCore includes a **Skills** subsystem for exposing curated “how to” content
to the model in a safe, auditable way.

Skills are stored as Markdown files (with frontmatter) and optional companion
files (scripts/references/assets). AgentCore:

- lists skill metadata (`Store#list_skills`)
- loads skill body + file index (`Store#load_skill`)
- reads skill files (text or bytes, size-limited)

AgentCore does **not** execute skill scripts. Execution remains an app concern.

## Store backends

### FileSystemStore

`Resources::Skills::FileSystemStore` loads skills from one or more directories:

```ruby
store =
  AgentCore::Resources::Skills::FileSystemStore.new(dirs: "/path/to/skills", strict: true)
```

The store enforces:

- relative-path safety (no `..` traversal)
- realpath validation (prevents symlink escapes)
- size caps (via `max_bytes:` parameters)

## `<available_skills>` prompt fragment

If you provide a `skills_store` to the agent, AgentCore’s default pipeline will
append an `<available_skills>` XML fragment to the system prompt, containing
metadata only.

```ruby
agent = AgentCore::Agent.build do |b|
  b.provider = provider
  b.skills_store = store
  b.include_skill_locations = false # opt-in
end
```

`include_skill_locations` is **false by default** to avoid leaking filesystem
paths in prompts.

### Size note (no built-in limits)

`<available_skills>` currently has **no built-in `max_skills` / `max_bytes`**
limit. If you have many skills (or very long descriptions), the injected
fragment can become large and may push prompts over the context window.

Recommended mitigations:

- Prefer exposing skills via tools (`skills.list` / `skills.load`) and keep
  `<available_skills>` minimal (or disable it entirely).
- If you still want the fragment, wrap your store so `list_skills` returns a
  curated subset (or add caching + trimming in your app).

## Skills as tools (auditable + authorization-aware)

AgentCore can expose skills via native tools, which flow through the same tool
policy + pause/resume confirmation + trace hooks as other tools.

```ruby
skills_tools = AgentCore::Resources::Skills::Tools.build(store: store)

registry = AgentCore::Resources::Tools::Registry.new
registry.register_many(skills_tools)
```

Tools:

- `skills.list` — metadata list (JSON text)
- `skills.load` — skill body markdown + files index (JSON text)
- `skills.read_file` — reads a file from a skill directory
  - returns text when UTF-8-ish
  - returns a multimodal base64 block for binary files (`image/*`, `audio/*`,
    otherwise `document`)

File media types are inferred via `Marcel` (filename-based inference).

## Security notes

- Prefer **tool policy confirmation** for `skills.read_file` in production.
- Set conservative size caps (`max_body_bytes`, `max_file_bytes`) when building
  tools.
- Treat skill contents as potentially sensitive: log/trace with redaction
  (`Observability::TraceRecorder` `redactor:`).
