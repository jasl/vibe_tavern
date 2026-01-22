---
name: rails-tdd-minitest
description: TDD workflow for Rails using Minitest + fixtures (no RSpec).
---

# Rails TDD (Minitest)

Use this skill when writing new code or fixing bugs.

## Core Rules

- Tests first (RED -> GREEN -> REFACTOR).
- Use Minitest + fixtures (do not introduce RSpec).
- Prefer the narrowest test command (fast feedback).
- Test behavior (public API), not private implementation details.

## Where Tests Go

- Models: `test/models/**/*_test.rb`
- Controllers: `test/controllers/**/*_test.rb`
- Integration/requests: `test/integration/**/*_test.rb`
- System: `test/system/**/*_test.rb`
- Services: `test/services/**/*_test.rb`
- Queries: `test/queries/**/*_test.rb`
- Presenters: `test/presenters/**/*_test.rb`

## Workflow

1) Pick the smallest test type that proves the behavior
   - Prefer unit tests (model/service/query/presenter) unless the behavior is
     inherently controller/system.

2) Write a failing test with a clear name
   - Prefer one assertion theme per test.
   - Make fixtures explicit (avoid hidden setup).

3) Run the test (it must fail for the right reason)
   - `bin/rails test test/...`

4) Implement the smallest change to pass
   - Keep diffs small.
   - Avoid opportunistic refactors.

5) Run the test again (must pass)

6) Refactor only while green
   - Extract code only if it makes the next change safer.
   - Re-run tests after each meaningful refactor.

## Minitest Patterns

### Assertion Basics

```ruby
assert something
refute something
assert_equal expected, actual
assert_nil value
assert_match(/pattern/, string)
assert_includes collection, value
assert_raises(SomeError) { ... }
```

### DB Changes

```ruby
assert_difference -> { Model.count }, +1 do
  # action
end

assert_no_difference -> { Model.count } do
  # action
end
```

### Service Result Shape (Preferred)

Services should return `Result` (see `app/services/result.rb`), typically via
`Result.success(...)` / `Result.failure(...)`.

Keep assertions small and explicit:

```ruby
assert result.success?
assert_equal "some_code", result.code
assert_equal expected, result.value
assert_includes result.errors, "message"
```

## Commands

- Single file:
  - `bin/rails test test/models/user_test.rb`
- Single test (by line):
  - `bin/rails test test/models/user_test.rb:42`
- Single directory:
  - `bin/rails test test/services/`
- Full suite:
  - `bin/rails test`
