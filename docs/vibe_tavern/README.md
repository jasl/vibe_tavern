# TavernKit::VibeTavern Docs

This directory contains the docs for `TavernKit::VibeTavern`: a
provider-tolerant prompt + tool/directives layer that prioritizes:

- reliability across models/providers
- debuggability (traceable request boundaries)
- reproducibility (deterministic tests + optional eval harnesses)

Audience:
- this repo’s developers (you + me)
- developers (including AI agents) working inside this repo

## Reading order

### Design / architecture

1) `docs/vibe_tavern/design/architecture.md`
2) `docs/vibe_tavern/design/skills.md`
3) `docs/vibe_tavern/design/mcp.md`
4) `docs/vibe_tavern/design/token-estimation.md`
5) `docs/vibe_tavern/design/macros.md`
6) `docs/vibe_tavern/design/language-policy.md`

### Case studies (reliability)

7) `docs/vibe_tavern/case_studies/tool-calling.md`
8) `docs/vibe_tavern/case_studies/directives.md`
9) (Optional) `docs/vibe_tavern/case_studies/ruby-llm.md`

### Guides

10) `docs/vibe_tavern/guides/model-selection.md`

Product backlog (intentionally not locked in yet):
- `docs/todo/vibe_tavern/deferred-agentic-generation.md`
- `docs/todo/vibe_tavern/local-openai-compatible-providers.md`
- `docs/todo/vibe_tavern/a2ui-directives-compiler.md`

## Evaluation harnesses

These scripts are optional (networked) and are used to build a
model×sampling-profile capability matrix:

- Tool calling: `script/llm_tool_call_eval.rb`
- Directives: `script/llm_directives_eval.rb`
- Full preset (runs both): `script/llm_vibe_tavern_eval.rb`
- Model selection notes: `docs/vibe_tavern/guides/model-selection.md`
- Shared sampling profiles: `script/openrouter_sampling_profiles.rb`

Deterministic (CI) coverage is under `test/tool_calling/`.
