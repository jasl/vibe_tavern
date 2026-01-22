---
name: rails-security-review
description: Rails security checklist (input handling, authZ, secrets, scans).
---

# Rails Security Review

Use this skill when adding endpoints, handling user input, working with auth,
or touching anything security-sensitive.

## Non-Negotiables

- No secrets in git (API keys, passwords, tokens).
- No mass-assignment surprises (use strong params).
- No SQL injection (use bind params / hash conditions).
- No XSS bypasses (avoid `html_safe`; sanitize intentionally).

## Checklist

### Secrets

- Prefer Rails credentials for app secrets.
- `.env*` stays uncommitted (this repo ignores `/.env*`).

### Authorization

- Every write action should have an explicit authorization decision.
- Scope reads to the current user/account (avoid unscoped `Model.all`).

### Strong Params

- Use `params.require(...).permit(...)`.
- Avoid `permit!`.

### SQL Injection

- Good:
  - `where(email: params[:email])`
  - `where("email = ?", params[:email])`
- Avoid:
  - `where("email = '#{params[:email]}'")`

### XSS

- Rails escapes by default; keep it that way.
- Avoid `html_safe` unless you can prove the input is safe.
- If rendering user-provided HTML, sanitize explicitly.

### CSRF

- Keep CSRF protection enabled for browser-based controllers.
- If building JSON endpoints, be explicit about CSRF strategy.

### File Uploads (Active Storage)

- Validate content type and size.
- Never trust client-provided filenames.

## Verification Commands

- Security scan:
  - `bin/brakeman`
- Dependency audit:
  - `bin/bundler-audit`
