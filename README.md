# Vibe Tavern

Rails app + embedded prompt-building library.

This repo contains:
- a Rails rewrite (app code in `app/`)
- an embedded gem: `lib/tavern_kit/` (TavernKit, the prompt-building core)
- reference sources under `resources/` (ignored / for local comparison only)

## Quickstart

Use the repo entrypoints (they encode local assumptions):

```sh
bin/setup   # deps + credentials + db:prepare (idempotent)
bin/dev     # dev Procfile + rails server
```

## Tests / CI

```sh
bin/ci
```

Useful narrower commands:

```sh
bin/rails test
bin/rails test:system
bin/rubocop
```

Embedded gem (TavernKit):

```sh
cd lib/tavern_kit && bin/setup
cd lib/tavern_kit && bundle exec rake test
```

## Rewrite docs

- Roadmap (waves): `docs/plans/2026-01-29-tavern-kit-rewrite-roadmap.md`
- Rewrite doc index: `docs/rewrite/README.md`
- TavernKit gem README: `lib/tavern_kit/README.md`

## License

MIT. See `LICENSE.txt`.
