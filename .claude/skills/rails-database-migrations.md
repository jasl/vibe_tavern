---
name: rails-database-migrations
description: Safe Rails migrations for Postgres (reversible, low-lock, indexed).
---

# Rails Database Migrations (Postgres)

Use this skill whenever changing schema.

## Safety Principles

- Migrations should be reversible.
- Avoid long-running locks in production.
- Index foreign keys.
- For large tables, prefer multi-step migrations (deploy code between steps).

Repo note:

- This app uses multiple databases (primary/queue/cable). Default migrations go
  in `db/migrate`. Avoid editing `db/*_migrate` (queue/cable/cache) unless you
  are explicitly upgrading Solid* dependencies.

## Common Safe Patterns

### Add Column (Existing Table)

Prefer adding nullable first, backfilling, then enforcing NOT NULL in a later
migration.

### Add NOT NULL (Two-Step)

1) Add column allowing NULL.
2) Backfill in batches.
3) Enforce `null: false`.

### Concurrent Index

```ruby
class AddIndexToWidgetsOnAccountId < ActiveRecord::Migration[8.2]
  disable_ddl_transaction!

  def change
    add_index :widgets, :account_id, algorithm: :concurrently, if_not_exists: true
  end
end
```

### Backfill In Batches

Avoid loading app models with changing behavior; use a minimal AR class inside
the migration when needed.

```ruby
class BackfillWidgetsStatus < ActiveRecord::Migration[8.2]
  disable_ddl_transaction!

  class Widget < ActiveRecord::Base
    self.table_name = "widgets"
  end

  def up
    Widget.unscoped.where(status: nil).in_batches(of: 1000) do |relation|
      relation.update_all(status: 0)
      sleep 0.01
    end
  end

  def down
    # Data migration: no-op
  end
end
```

## Commands

- Generate:
  - `bin/rails generate migration AddFooToBars foo:string`
- Run:
  - `bin/rails db:migrate`
- Rollback:
  - `bin/rails db:rollback`
- Status:
  - `bin/rails db:migrate:status`
- Reset:
  - `bin/rails db:reset`
