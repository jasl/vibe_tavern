# Load Hooks Contract (Initialization / Registration)

Date: 2026-02-09

TavernKit provides a small, Rails-like **load hooks** mechanism for wiring
application-specific infrastructure into pipelines without introducing a hard
dependency from Core → App code.

This is intended for **boot-time / load-time registration** (e.g. registries,
sanitizers, adapters), not for per-request behavior.

## Why load hooks exist

Some features are owned by the application (or a consumer layer) but need a
consistent way to register their rules/handlers into shared infrastructure.

Example:
- A middleware introduces a semantic tag (e.g. `<lang code="...">...</lang>`)
- The output post-processor must understand that tag, but the post-processor
  should remain generic and extensible.

Load hooks let the middleware register its rules into an app-owned registry at
initialization time.

## API

```ruby
TavernKit.on_load(:some_scope, id: :unique_id) { |payload| ... }
TavernKit.run_load_hooks(:some_scope, payload_object)
```

Semantics:
- `run_load_hooks(scope, payload)` sets/replaces the current payload for the
  scope and executes all hooks registered for that scope.
- `on_load(scope)` registers a hook; if the scope has already been run, the
  hook is executed immediately with the current payload.
- `id:` (recommended) de-duplicates hooks for reloadable code paths (last
  write wins).

## Scope naming

Scopes are Symbols. Consumers should choose a stable scope name, e.g.:
- `:vibe_tavern`
- `:my_app`

## Contract: external input vs programmer errors

Load hooks are **programmer-facing**. If registration fails, it should fail
fast (raise). Tolerant behavior should be reserved for external inputs (user
text, imported JSON, provider responses).

## Relationship to build-time hooks (HookRegistry)

TavernKit also has build-time hooks via `TavernKit::HookRegistry` (used by
platform pipelines like SillyTavern).

Key difference:
- **Load hooks**: run at initialization time to register wiring/handlers.
- **HookRegistry**: runs during prompt building on a per-request `Prompt::Context`.

If you need to mutate prompt construction per-request, use pipeline middleware
or `HookRegistry`. If you need to register capabilities/handlers once, use load
hooks.

## Example: registering a sanitizer into an app registry

Consumer defines an infra object and runs hooks:

```ruby
infra = MyInfra.new(output_tags_registry: MyRegistry.new)
TavernKit.run_load_hooks(:my_scope, infra)
```

Middleware registers its rules:

```ruby
TavernKit.on_load(:my_scope, id: :"my_feature.register") do |infra|
  infra.output_tags_registry.register_sanitizer(:lang_spans, MyLangSpanSanitizer)
end
```
