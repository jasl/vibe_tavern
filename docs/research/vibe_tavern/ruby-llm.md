# RubyLLM evaluation (for VibeTavern)

This document summarizes a lightweight evaluation of RubyLLM as a potential
dependency for `TavernKit::VibeTavern`.

## TL;DR

- For our current scope (OpenAI-compatible: OpenAI/OpenRouter/vLLM/llama.cpp),
  **RubyLLM does not replace SimpleInference** in the `TavernKit::VibeTavern`
  infra layer.
- RubyLLM could still be valuable **at the app layer** later, mainly to support
  non-OpenAI-compatible providers (Anthropic/Gemini/Bedrock) and multimodal
  inputs, while keeping VibeTavern as the reliability/runner layer.

## Context

VibeTavern’s priorities:

- reliability across vendors/models (presets + guardrails)
- debuggability (traceable request/response boundaries)
- reproducibility (eval harness that controls raw request options)
- strict separation: `lib/tavern_kit/vibe_tavern` is infra; app injects business

Current infra client:

- `vendor/simple_inference` (OpenAI-compatible transport/client)

Schema DSL / validation:

- `vendor/easy_talk` (JSON Schema + runtime validation + error formatting)

## What RubyLLM brings (relevant)

- A high-level, “one API for many providers” SDK (OpenAI, OpenRouter, Ollama,
  Anthropic, Gemini, etc).
- Tool calling and structured outputs as convenience features.
- Streaming API (chunk callbacks) and Rails integration helpers.

## Why we are not adopting RubyLLM inside `lib/tavern_kit/vibe_tavern` (now)

### 1) It’s the wrong abstraction layer for eval + presets

Our success-rate work depends on being able to:

- send raw OpenAI-compatible fields (tools/tool_choice/response_format/provider routing)
- intentionally toggle vendor-specific workarounds
- capture raw bodies/errors for post-analysis

RubyLLM’s design goal is to normalize providers and “make it easy”, which can
hide exactly the details we need to control during evaluation.

### 2) “Structured output” in RubyLLM is not our directives runner

RubyLLM’s schema mode mostly ensures “the output is JSON-ish” (it parses JSON
when a schema is set). VibeTavern directives require:

- stable envelope shape
- allowlist-based type validation + aliasing
- optional payload validation (EasyTalk)
- best-effort repair + fallback modes (json_schema/json_object/prompt_only)

That logic is VibeTavern-specific and stays useful regardless of client SDK.

### 3) RubyLLM Schema DSL is a separate gem (`ruby_llm-schema`)

The `ruby_llm` gem depends on `ruby_llm-schema` to provide `RubyLLM::Schema`.
That increases our dependency surface and is not required for our current needs
(we already have EasyTalk for Ruby-first schemas + validations).

### 4) Cross-provider schema quirks still need our hardening

RubyLLM Schema JSON includes keys like `strict` inside the schema object, and
its tool parameter schema generation can include `required: []`.

Some OpenAI-compatible backends are strict about JSON Schema subsets and may
reject unknown keys or empty `required`. VibeTavern already normalizes tool
schemas for compatibility (e.g. dropping empty `required`), and we would still
need this type of hardening even if RubyLLM were used.

## Decision (current)

- Keep `SimpleInference` as the infra HTTP client for OpenAI-compatible APIs.
- Keep `EasyTalk` for schema definition and runtime validation.
- Do not support RubyLLM-style schema providers in `TavernKit::VibeTavern::JsonSchema`.
  If an app wants to use RubyLLM schema DSL, it can pass a plain Hash (extracting
  the `:schema` portion) at the app boundary.

## When to reconsider RubyLLM (app layer)

Re-evaluate RubyLLM if we need any of:

- first-class support for non-OpenAI-compatible providers (native Anthropic/Gemini)
- multimodal/attachments support beyond our current scope
- a maintained model catalog/capability registry in production code

## If we introduce it later: recommended boundary

- RubyLLM should live in the Rails app layer as a provider SDK.
- VibeTavern remains the runner/protocol layer (ToolLoopRunner + Directives::Runner).
- If needed, add a small adapter so VibeTavern can call a RubyLLM-backed client
  while still preserving:
  - raw request override control (for eval/workarounds)
  - trace capture (request/response metadata + errors)

## Sources reviewed

- `resources/ruby_llm` (copied RubyLLM source for offline review)
- `ruby_llm-schema` gem source (schema DSL + JSON output shape)
