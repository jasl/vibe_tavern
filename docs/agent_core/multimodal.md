# Multimodal Content (AgentCore)

AgentCore messages can be either:

- plain text (`Message#content` is a `String`)
- multimodal (`Message#content` is an `Array` of content blocks)

Supported block types in Phase 1:

- `TextContent`
- `ImageContent` (`:base64` or `:url`)
- `DocumentContent` (`:base64` or `:url`)
- `AudioContent` (`:base64` or `:url`, optional transcript)

## MIME (`media_type`)

For `:base64` sources, `media_type` is required.

For `:url` sources, `media_type` is optional. You can still ask for a best-effort
inference (based on filename/URL) via:

- `ImageContent#effective_media_type`
- `DocumentContent#effective_media_type`
- `AudioContent#effective_media_type`

These methods use `marcel` under the hood.

## Safety: URL sources (SSRF / unwanted fetch)

AgentCore does **not** fetch URLs. However, some provider adapters or app code
may fetch URL-based media sources. Treat URL sources as untrusted input and
apply a policy at the app layer.

AgentCore provides a small policy surface via global config:

```ruby
AgentCore.configure do |c|
  # 1) Disable URL media sources entirely (recommended default for many apps)
  c.allow_url_media_sources = false

  # 2) Or restrict schemes (e.g., https only)
  c.allowed_media_url_schemes = %w[https]

  # 3) Or implement a custom validator hook
  c.media_source_validator = lambda do |block|
    # block is ImageContent / DocumentContent / AudioContent
    true
  end
end
```

Suggested validations for URL sources (app-specific):

- allowlist hosts/domains
- block private network ranges (SSRF)
- enforce https-only
- enforce size/time limits when fetching
