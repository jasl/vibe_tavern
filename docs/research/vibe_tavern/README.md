# TavernKit::VibeTavern — Research / Case Study Notes

This directory is a **research / case study** write-up of building
`TavernKit::VibeTavern`: a provider-tolerant prompt + tool/directives layer that
prioritizes **reliability, debuggability, and reproducibility**.

Audience:
- this repo’s developers (you + me)
- shareable notes for the community (design tradeoffs + reliability techniques)

## Reading order

1) `docs/research/vibe_tavern/architecture.md`
2) `docs/research/vibe_tavern/macros.md`
3) `docs/research/vibe_tavern/tool-calling.md`
4) `docs/research/vibe_tavern/directives.md`

Product backlog (not research, intentionally not locked in yet):
- `docs/todo/vibe_tavern/deferred-agentic-generation.md`
- `docs/todo/vibe_tavern/local-openai-compatible-providers.md`

## Evaluation harnesses

These scripts are optional (networked) and are used to build a
model×sampling-profile capability matrix:

- Tool calling: `script/llm_tool_call_eval.rb`
- Directives: `script/llm_directives_eval.rb`
- Full preset (runs both): `script/llm_vibe_tavern_eval.rb`
- Shared sampling profiles: `script/openrouter_sampling_profiles.rb`

Deterministic (CI) coverage is under `test/tool_calling/`.
