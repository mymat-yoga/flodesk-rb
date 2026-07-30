# Changelog

## [Unreleased]

## [0.1.0] - 2026-07-29

Initial release.

> **The public API is unstable until it has been exercised against a live Flodesk
> account.** Everything here is verified against the vendored API description and
> WebMock stubs, but only the `401` envelope has been confirmed against the real
> service. Expect breaking changes in `0.1.x`.

### Added

- `Flodesk::Client` — explicit, frozen, thread-safe. No global configuration, so
  per-tenant API keys are straightforward.
- Full coverage of all 25 documented operations across six resources:
  subscribers, segments, custom fields, workflows, webhooks and campaigns
  (including the Canva endpoints).
- API-key (HTTP Basic) authentication, behind a strategy seam so OAuth2 can be
  added later without a breaking change.
- Immutable `Data.define` value objects, each exposing `#to_h` with the raw
  payload — so a field Flodesk adds is reachable without a gem release.
- `BatchResult` with explicit partial-failure semantics. `batch_upsert` raises
  `Flodesk::PartialFailureError` when any record fails, carrying the successes;
  `raise_on_failure: false` returns the result quietly.
- Per-endpoint idempotency declarations driving retries. `POST /segments`,
  `POST /custom-fields`, `POST /webhooks` and `POST /campaigns/canva` are never
  retried; the last is never retried even on `429`, because a retry could send a
  campaign to the entire list twice.
- One uniform `page:` / `per_page:` interface across every list endpoint,
  translating to `per_page`, `perPage` or PascalCase filters as each requires.
- Opt-in `auto_paging_each` returning a lazy `Enumerator`. Not the default,
  because traversing a large collection can consume the whole rate-limit budget.
- Webhook handling with **mandatory** verification — Flodesk signs nothing — via
  either a constant-time token-in-path check or authoritative re-fetch, plus a
  composed SHA-256 dedupe key since events carry no unique id.
- Rails integration: `rails g flodesk:install`, a Railtie, `flodesk.request`
  `ActiveSupport::Notifications` events, and opt-in WebMock test helpers. All
  loaded conditionally; the gem declares **no runtime dependencies**.
- PII redaction throughout logging and instrumentation: `email`,
  `custom_fields` and `optin_ip` never appear, including when an email is
  embedded in a request path.
- RBS signatures for the public surface.
- A contract spec that walks the vendored `openapi.json` and fails the build when
  client coverage drifts from the documented API.

### Notes on the API this wraps

Behaviors the client absorbs, recorded here because they are easy to
rediscover the hard way:

- `POST /subscribers` is an upsert returning `200` for both creation and update,
  and never reports which occurred.
- `POST /subscribers/batch` reports per-record failures inside a `200`.
- `GET /workflows` spells its page-size parameter `perPage`; `GET /campaigns`
  uses PascalCase filters while keeping snake_case pagination.
- `GET /workflows`'s `statuses` filter is comma-separated, not repeated keys, and
  has its own enum (`active`/`paused`/`draft`) distinct from the subscriber and
  campaign status enums.
- `POST /webhooks` requires a `name` field.
- Custom field values are typed `string` only.
- Rate-limit responses include `X-Fd-RateLimit-Limit` and `-Remaining` but **no
  reset header**, so no correct backoff interval is computable.
- The description declares no error-body schema anywhere; the `{code, message}`
  envelope was established by probing the live API.

[Unreleased]: https://github.com/jimiray/flodesk-rb/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jimiray/flodesk-rb/releases/tag/v0.1.0
