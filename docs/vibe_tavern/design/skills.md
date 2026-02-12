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
`license`, `compatibility`, `allowed_tools`, and `metadata`.

Code:
- `lib/tavern_kit/vibe_tavern/tools/skills/frontmatter.rb`

## Discovery + loading

Skills are backed by an app-injected `Tools::Skills::Store` implementation.

The default filesystem implementation is `Tools::Skills::FileSystemStore`, which scans
configured skill roots for **immediate subdirectories** containing `SKILL.md`.

- `#list_skills` loads only frontmatter and returns `SkillMetadata`.
  - for safety, it reads only a bounded prefix of `SKILL.md` to parse frontmatter
- `#load_skill` loads the full Markdown body and indexes bundled files under:
  - `scripts/`
  - `references/`
  - `assets/`

Bundled files are indexed as relative paths one level deep (for example:
`references/foo.md`).

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
  <skill name="foo" description="..." />
</available_skills>
```

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
}
```

Code:
- `lib/tavern_kit/vibe_tavern/tools/skills/config.rb`
