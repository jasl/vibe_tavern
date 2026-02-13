# Agent Skills (SKILL.md)

Agent Skills are a **progressive-disclosure package format** used by
`TavernKit::VibeTavern` to offer optional, tool-fetched instructions/resources
to the model without inflating prompts at startup.

## Skill format

- A skill is a directory containing `SKILL.md`.
- `SKILL.md` must start with YAML frontmatter delimited by `---` lines, followed
  by a Markdown body.
- Required frontmatter keys:
  - `name` (String): must match the parent directory name
  - `description` (String)
- Name constraints:
  - length: 1–64
  - pattern: `\A[a-z0-9]+(?:-[a-z0-9]+)*\z`

Optional frontmatter keys are passed through into metadata objects:
`license`, `compatibility`, `allowed-tools` / `allowed_tools`, and `metadata`.

Notes:
- `allowed-tools` is the Agent Skills spec key; TavernKit also accepts
  `allowed_tools` for compatibility.
- Spec form for `allowed-tools` is a space-delimited string, but TavernKit also
  accepts a YAML array of strings.
- In strict mode, `metadata` must be a string-to-string map.
- In strict mode, `description` is limited to 1024 chars and `compatibility` is
  limited to 500 chars.

Code:
- `lib/tavern_kit/vibe_tavern/tools/skills/frontmatter.rb`

## Discovery + loading

Skills are backed by an app-injected `Tools::Skills::Store` implementation.

The default filesystem implementation is `Tools::Skills::FileSystemStore`, which scans
configured skill roots for **immediate subdirectories** containing `SKILL.md`.

- `#list_skills` loads only frontmatter and returns `SkillMetadata`.
  - for safety, it reads only a bounded prefix of `SKILL.md` to parse frontmatter
- `#load_skill` loads `SKILL.md` and indexes bundled files under:
  - `scripts/`
  - `references/`
  - `assets/`

Bundled files are indexed as relative paths one level deep (for example:
`references/foo.md`).

`#load_skill` supports a `max_bytes:` limit to bound how much of `SKILL.md` is
read into memory. When exceeded, the returned `Skill` is marked
`body_truncated: true` (and tool results may emit a `CONTENT_TRUNCATED`
warning).

Code:
- `lib/tavern_kit/vibe_tavern/tools/skills/store.rb`
- `lib/tavern_kit/vibe_tavern/tools/skills/file_system_store.rb`
- `lib/tavern_kit/vibe_tavern/tools/skills/skill_metadata.rb`
- `lib/tavern_kit/vibe_tavern/tools/skills/skill.rb`

## Prompt injection (metadata only)

`PromptBuilder::Steps::AvailableSkills` injects a machine-readable system block
containing only skill name/description (and optionally `location`):

```xml
<available_skills>
  <skill>
    <name>foo</name>
    <description>...</description>
  </skill>
</available_skills>
```

When `include_location: true`, the injected `location` value is the absolute
path to `SKILL.md` (not the skill directory).

This is the only prompt-time exposure. Full skill bodies and bundled files are
retrieved via tools.

Code:
- `lib/tavern_kit/vibe_tavern/prompt_builder/steps/available_skills.rb`

## Tools (model-facing)

The Skills tool surface is exposed via `Tools::Skills::ToolDefinitions` (wired
by `ToolsBuilder`):

- `skills_list`: list skill metadata
- `skills_load`: load `SKILL.md` body (progressive disclosure)
- `skills_read_file`: read a bundled file under `scripts/`, `references/`,
  `assets/`
- `skills_run_script`: stub only (returns `NOT_IMPLEMENTED`)

Tool execution is owned by `ToolCalling::Executors::SkillsExecutor`.

Code:
- `lib/tavern_kit/vibe_tavern/tools/skills/tool_definitions.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/executors/skills_executor.rb`

## File read security

`skills_read_file` (and `Store#read_skill_file`) enforce:

- one-level deep relative paths: `\A(scripts|references|assets)/[^/]+\z`
- no absolute paths or `..`
- containment checks (including symlink escapes via `realpath`)
- output size limit (default: 200_000 bytes)

`FileSystemStore#list_skills` also enforces containment checks for discovered
skill directories and `SKILL.md` itself to prevent symlink escapes during
discovery.

## Configuration

Skills are configured via `context[:skills]` (symbol keys). When enabled,
`store:` is required; VibeTavern does not scan directories implicitly.

```ruby
store =
  TavernKit::VibeTavern::Tools::Skills::FileSystemStore.new(
    dirs: ["/abs/path/to/skills"],
    strict: true,
  )

context[:skills] = {
  enabled: true,
  store: store,
  include_location: false,
  allowed_tools_enforcement: :off,
  allowed_tools_invalid_allowlist: :ignore,
}
```

## Execution-time allowed-tools enforcement (optional)

TavernKit can optionally treat `allowed-tools` as a runtime policy that
contracts the available tool surface *after* a successful `skills_load`.

Semantics:
- Default: **off** (no behavior change unless explicitly enabled).
- Activation: only after a successful `skills_load` tool call (`ok: true`).
- Scope: the current `ToolLoopRunner` run only (in-memory; not persisted).
- Multi-skill: **last-wins** (the last successfully loaded skill controls the policy).
- Baseline tools are always allowed to avoid deadlocks:
  - `skills_list`, `skills_load`, `skills_read_file`

When enabled, the policy applies both to:
- **Exposure**: the `tools:` list sent to the model on subsequent turns.
- **Enforcement**: tool execution (blocked tool calls return `TOOL_NOT_ALLOWED`).

Matching rules:
- Exact tool names are supported (e.g. `state_get`).
- Simple glob patterns are supported as a TavernKit extension:
  - any entry containing `*`, `?`, or `[` is treated as a glob (via `File.fnmatch?`)
  - examples: `state_*`, `mcp_*`, `mcp_srv__*`
- `.` is canonicalized to `_` for matching (for robustness with dotted tool names).

Invalid allowlist behavior:
- If `allowed-tools` is non-empty but matches **no non-baseline tools**:
  - `allowed_tools_invalid_allowlist: :ignore` (default): ignore enforcement (no contraction)
  - `allowed_tools_invalid_allowlist: :enforce`: enforce baseline-only (very restrictive)
  - `allowed_tools_invalid_allowlist: :error`: fail the run with `ToolUseError`

Observability:
- `ToolLoopRunner` emits:
  - `:skills_allowed_tools_policy_changed` on policy activation/deactivation
  - `:tool_call_blocked` when a tool call is blocked by allowed-tools
- `ToolLoopRunner` trace entries include a `skills_allowed_tools` section (mode, enforced, skill_name, allow_set_count, ignored_reason).
- `skills_load` tool results may include warnings:
  - `ALLOWED_TOOLS_ENFORCED` when enforcement is active
  - `ALLOWED_TOOLS_IGNORED` when enforcement was ignored due to `NO_MATCHES`

Code:
- `lib/tavern_kit/vibe_tavern/tools/skills/config.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_loop_runner.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/policies/skills_allowed_tools_policy.rb`
- `lib/tavern_kit/vibe_tavern/tools_builder/runtime_filtered_catalog.rb`

## Host governance (tool policy)

`allowed-tools` is authored by skill packages. In SaaS settings, it is not a
replacement for host-owned authorization and audit controls.

For host control-plane decisions (allow/deny/confirm), use the tool policy hook
configured via `context[:tool_calling]` (see `docs/vibe_tavern/design/governance.md`).

Relationship when both are enabled:
- Exposure: tool surface is contracted by skills `allowed-tools` first, then filtered by the host policy.
- Enforcement: tool execution is blocked if either:
  - the tool is not in the active skills allow-set (`TOOL_NOT_ALLOWED`), or
  - the host policy denies/requests confirmation (`TOOL_POLICY_DENIED` / `TOOL_CONFIRMATION_REQUIRED`).

## SaaS host TODO (multi-tenant)

To safely run third-party skills in a multi-tenant environment, the host
application must implement:

- Skill package governance: installation approval, provenance, and per-tenant/per-workspace isolation.
- Storage isolation: ensure skills roots and any cached artifacts are scoped to tenant/workspace and cannot be used to escape or exfiltrate host data.
- Authorization: enforce host-owned allow/deny/confirm policies for tool usage; do not rely on `allowed-tools` alone.
- Auditing: record skill discovery/loading/file reads and policy decisions (redacted, structured, append-only storage).

Out of scope here:
- `skills_run_script` sandboxing, confirmations, and resource controls (host-controlled).
