# TavernKit Docs

This folder contains the long-form documentation for the embedded `tavern_kit`
gem (the gem root is `vendor/tavern_kit/` in this repo). Paths in this section
are relative to the gem root.

It is meant to be the stable home for:

- architecture and interface contracts
- SillyTavern / RisuAI compatibility notes
- security / performance guardrails
- backlogs (explicit non-goals + future work)

For Rails integration work (the app rewrite), see the top-level `docs/` folder.

## Start Here

- Reference sources (pinned upstream commits/specs): `docs/reference-sources.md`
- Core interface design: `docs/core-interface-design.md`
- Pipeline observability/debugging: `docs/pipeline-observability.md`
- Prompt orchestration contracts (dialects/trimming/injection): `docs/contracts/prompt-orchestration.md`
- Load hooks contract (initialization/registration): `docs/contracts/load-hooks.md`
- Compatibility matrices:
  - SillyTavern: `docs/compatibility/sillytavern.md`
  - RisuAI: `docs/compatibility/risuai.md`
- Known deltas vs upstream:
  - SillyTavern: `docs/compatibility/sillytavern-deltas.md`
  - RisuAI: `docs/compatibility/risuai-deltas.md`
- Security + performance audit notes: `docs/security-performance-audit.md`
- Rewrite completion audit: `docs/rewrite-audit.md`
- Backlogs (out of scope / future work): `docs/backlogs.md`
