# EasyTalk ActiveModel::Type Adapter (2026-01-28)

## Goal
Replace `serialize :attr, coder: EasyTalkCoder.new(Schema)` with a native
ActiveModel::Type adapter while keeping EasyTalk as the **single source of
truth** for schema + validations + UI metadata.

## Status
- Implemented `EasyTalk::ActiveModelType` in `vendor/easy_talk/lib/easy_talk/active_model_type.rb`.
- Added `to_type` to `EasyTalk::Model` and `EasyTalk::Schema`.
- Documented in `vendor/easy_talk/README.md`.

## Usage (target)
```ruby
class Character < ApplicationRecord
  attribute :data, TavernKit::Character::Schema.to_type
end

class Space < ApplicationRecord
  attribute :prompt_settings, ConversationSettings::SpaceSettings.to_type
end
```

## Casting Behavior (best-effort)
- JSON string / Hash → schema instance
- Primitive types (`String`, `Integer`, `Float`, `BigDecimal`, `T::Boolean`) cast
  via `ActiveModel::Type`
- `T::Array[Type]` casts each element
- `T::Tuple[...]` casts by position
- Nested EasyTalk schemas/models are instantiated recursively
- Unknown keys are preserved (pass-through)

## Limitations (current)
- Composition types (`T::AnyOf` / `T::OneOf` / `T::AllOf`) are not specially
  resolved during casting; values pass through unless they match a supported
  primitive or nested schema.
- Typed hashes (`T::Hash[...]`) are not cast (pass-through).
- This adapter does **not** change EasyTalk validation behavior; it only
  improves Rails attribute casting.

## Migration Plan
1. Add `attribute :foo, SchemaClass.to_type` alongside existing `serialize`.
2. Remove the `serialize` + `EasyTalkCoder` lines once coverage is in place.
3. Add characterization tests for JSON persistence/round-trip (especially for
   boolean/integer fields coming from UI as strings).

## Rails JSON Field Mapping (Playground parity)
- `Character.data` → `TavernKit::Character::Schema.to_type`
- `Character.authors_note_settings` → `ConversationSettings::AuthorsNoteSettings.to_type`
- `Space.prompt_settings` → `ConversationSettings::SpaceSettings.to_type`
- `Preset.generation_settings` → `ConversationSettings::LLM::GenerationSettings.to_type`
- `Preset.preset_settings` → `ConversationSettings::PresetSettings.to_type`
- `SpaceMembership.settings` → `ConversationSettings::ParticipantSettings.to_type`

## Next Enhancements (if needed)
- Add optional strict casting mode for unions and typed hashes.
- Add a dedicated array type helper if top-level JSON arrays become first-class
  attributes in the Rails models.
