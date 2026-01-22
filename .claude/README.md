# Project Local Claude Config

This repo keeps Claude Code-style config files local to the project to avoid
polluting `~/.claude`.

- Agents live in `.claude/agents/`
- Skills live in `.claude/skills/`

This is intentionally small and tailored to this codebase.

Primary source of truth for constraints and architecture:

- `CLAUDE.md`

Included skills:

- `.claude/skills/vibe-tavern-guardrails.md`
- `.claude/skills/rails-tdd-minitest.md`
- `.claude/skills/rails-security-review.md`
- `.claude/skills/rails-database-migrations.md`
