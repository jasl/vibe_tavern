# StoreModel Evaluation (2026-01-28)

## Context
We need a safe, typed, validated way to access JSONB fields in Rails models without custom coders. We also need nested schemas and future-proofed UI/schema metadata (x-ui/x-storage) currently provided by EasyTalk.

## What StoreModel Provides (from `resources/store_model`)
- Strongly-typed JSON attribute access via ActiveModel Attributes API.
- ActiveModel validations on the JSON-backed model.
- Nested models (models inside models), arrays/hashes of models.
- Polymorphic models via `one_of` / `union` with discriminators.
- Unknown attribute capture + optional serialization control.
- Integrates with ActiveRecord attributes (`attribute :settings, Settings.to_type`).

## Key Advantages
- **No custom coder needed**: uses ActiveModel::Type to serialize/deserialize JSON.
- **Strong typing** with standard Rails types + custom types.
- **Validations** with error merging strategies into parent model.
- **Nested structures** are supported (unlike Rails 8.2 `has_json`).
- **Unknown keys** can be preserved for forward/backward compatibility.

## Key Gaps / Risks
- **No JSON Schema / UI metadata**: EasyTalk’s `x-ui`/`x-storage` and schema registry are not present. If UI generation depends on schema metadata, we would need a parallel schema or build a generator from StoreModel definitions.
- **Dirty tracking caveat**: mutating nested StoreModel objects may require manual `*_will_change!` or reassignment (documented in StoreModel README).
- **Rails 7.2+ nested attributes issue**: StoreModel docs mention needing DB schema loaded before boot when using `accepts_nested_attributes_for`. This may still apply to Rails 8.2 and is a potential DX hazard in CI and new env setup.
- **Unknown attributes are allowed by default**: Good for compatibility, but weaker safety unless we add stricter handling.

## Current EasyTalk + EasyTalkCoder Approach (Playground)
- Uses `serialize :jsonb, coder: EasyTalkCoder.new(SchemaClass)` for JSONB columns.
- EasyTalk provides a single schema source with JSON Schema output and execution-time validation.
- Conversation settings extend EasyTalk to include `x-ui` and `x-storage` for schema-driven UI and storage mapping (`ConversationSettings::Base`).
- Schema bundle is already wired into UI rendering and server-side field enumeration.
- Works for nested schemas via `ConversationSettings::NestedSchemaSupport` (custom extension).

## Relationship to Rails 8.2 `has_json`
- The local Rails 8.2 source (`resources/rails/activemodel/lib/active_model/schematized_json.rb`) explicitly states **no nesting** and only boolean/integer/string. So `has_json` cannot represent current nested EasyTalk schemas.
- StoreModel **does** support nested structures, so it is a closer functional match to EasyTalk than `has_json`.

## Fit With Current Direction
- If we want typed JSON access with validations and no custom coder, **StoreModel is viable**.
- If we need JSON Schema metadata for UI or external tooling, StoreModel alone is insufficient.
- A hybrid could work: keep EasyTalk for schema/UI and generate StoreModel definitions (or embed StoreModel-like type casting) — but this adds complexity and dual sources of truth.

## Head-to-Head (StoreModel vs EasyTalkCoder)
**Schema + UI metadata**
- StoreModel: no JSON Schema output; no `x-ui`/`x-storage`.
- EasyTalkCoder: schema + UI metadata are first-class and already used in UI rendering.

**Nested settings**
- StoreModel: supported.
- EasyTalkCoder: supported via `ConversationSettings::NestedSchemaSupport`.

**Validation**
- StoreModel: ActiveModel validations + merge strategies.
- EasyTalk: auto-validations from schema definitions; already in use.

**Rails integration**
- StoreModel: ActiveModel::Type-based; no custom coder; AR attributes API.
- EasyTalkCoder: uses `serialize` and a custom coder; simpler but less integrated with AR attributes.

**Cross-project reuse**
- StoreModel: Rails-specific; would require a second schema layer for TavernKit gem.
- EasyTalk: already used in TavernKit gem schemas; keeps one source of truth.

## Recommendation (updated)
- **Do not switch to StoreModel** as the primary approach right now. It does not beat the current EasyTalk-based approach for our needs because it would force a second schema layer and break the existing schema-driven UI pipeline.
- **Keep EasyTalk as the single source of truth**, and improve Rails integration by adding an ActiveModel::Type for EasyTalk schemas (store_model-style) rather than adopting StoreModel wholesale.
- StoreModel remains a reference for design ideas (parent tracking, error merge strategies), but is not worth the migration cost given the existing EasyTalk ecosystem and cross-project reuse goals.
