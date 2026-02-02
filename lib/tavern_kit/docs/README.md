# TavernKit Docs

This folder contains the long-form documentation for the embedded `tavern_kit`
gem (`lib/tavern_kit/`). It is meant to be the stable home for:

- architecture and interface contracts
- SillyTavern / RisuAI compatibility notes
- security / performance guardrails
- backlogs (explicit non-goals + future work)

For Rails integration work (the app rewrite), see the top-level `docs/` folder.

## Start Here

- Reference sources (pinned upstream commits/specs): `lib/tavern_kit/docs/reference-sources.md`
- Core interface design: `lib/tavern_kit/docs/core-interface-design.md`
- Pipeline observability/debugging: `lib/tavern_kit/docs/pipeline-observability.md`
- Prompt orchestration contracts (dialects/trimming/injection): `lib/tavern_kit/docs/contracts/prompt-orchestration.md`
- Compatibility matrices:
  - SillyTavern: `lib/tavern_kit/docs/compatibility/sillytavern.md`
  - RisuAI: `lib/tavern_kit/docs/compatibility/risuai.md`
- Known deltas vs upstream:
  - SillyTavern: `lib/tavern_kit/docs/compatibility/sillytavern-deltas.md`
  - RisuAI: `lib/tavern_kit/docs/compatibility/risuai-deltas.md`
- Security + performance audit notes: `lib/tavern_kit/docs/security-performance-audit.md`
- Rewrite completion audit: `lib/tavern_kit/docs/rewrite-audit.md`
- Backlogs (out of scope / future work): `lib/tavern_kit/docs/backlogs.md`

