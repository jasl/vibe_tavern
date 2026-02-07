# Vibe Tavern

Rails app + embedded prompt-building library.

This repo contains:
- a Rails rewrite (app code in `app/`)
- an embedded gem: `vendor/tavern_kit/` (TavernKit, the prompt-building core)
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
cd vendor/tavern_kit && bin/setup
cd vendor/tavern_kit && bundle exec rake test
```

## Rewrite docs

- Rails rewrite docs: `docs/rewrite/README.md`
- VibeTavern research / case study docs: `docs/research/vibe_tavern/README.md`
- Product TODO / backlog docs: `docs/todo/README.md`
- TavernKit gem docs: `vendor/tavern_kit/docs/README.md`
- TavernKit gem README: `vendor/tavern_kit/README.md`

## License

MIT. See `LICENSE.txt`.
