## Why

No Ruby client exists for the Flodesk API, so every Rails app integrating with Flodesk hand-rolls `Net::HTTP` calls. That hand-rolling reliably gets three things wrong, because the API's own inconsistencies hide them:

- **Pagination is not uniform.** Most endpoints take `per_page`, but `GET /workflows` takes `perPage` and `GET /campaigns` takes `Search`/`OrderBy`/`Sort`/`Status`/`SharedAsTemplate` in PascalCase.
- **`POST /subscribers/batch` returns `200 OK` carrying both `successes[]` and `failures[]`.** A client that treats 2xx as success silently drops subscribers in production.
- **Retry safety is per-endpoint, not per-HTTP-method.** Most POSTs are idempotent upserts, but `POST /segments`, `POST /custom-fields`, `POST /webhooks` and `POST /campaigns/canva` create. A generic "retry POST on 5xx" wrapper can publish an email campaign to the entire list twice.

A gem that encodes this knowledge once is worth more than the HTTP plumbing it replaces.

## What Changes

- New gem namespace `Flodesk`. **BREAKING** relative to the current `bundle gem` skeleton: `Flodesk::Rb` is replaced by `Flodesk`. The RubyGems package name stays `flodesk-rb`. Nothing has been released, so no downstream consumers break.
- Full coverage of all 18 documented paths / 25 operations across six resources: subscribers, segments, custom fields, workflows, webhooks, campaigns (including the Canva endpoints).
- API-key (HTTP Basic) authentication only. OAuth2 is explicitly out of scope — see Non-goals.
- Zero runtime dependencies; `Net::HTTP` from stdlib.
- Immutable `Data.define` value objects for responses, each exposing `#to_h` with the raw parsed payload so a field Flodesk adds is reachable without a gem release.
- `BatchResult` for batch operations, raising `Flodesk::PartialFailureError` by default when any record fails; `raise_on_failure: false` returns the result object quietly.
- Per-endpoint idempotency declarations driving retry behavior; blanket POST retries are never performed.
- Explicit `Flodesk::Client` instances, thread-safe and with no gem-level global mutable state.
- Rails integration: install generator + Railtie, webhook handling, `ActiveSupport::Notifications` instrumentation, and shipped test helpers.
- Webhook verification is **mandatory**. The OpenAPI spec declares `security: []` for all three webhook events — no signature mechanism exists. The gem raises if constructed without a verification strategy rather than trusting unauthenticated POSTs.
- The upstream `openapi.json` is vendored as a test fixture and used as a contract oracle, so "full coverage" is enforced by the suite rather than asserted in a README.

## Capabilities

### New Capabilities

- `http-transport`: Connection handling, Basic auth, `User-Agent` identification, JSON encoding, timeouts, retry policy with per-endpoint idempotency, rate-limit header exposure, and thread safety.
- `error-handling`: Mapping the live `{code, message}` envelope to a rescuable error hierarchy, with graceful degradation when the shape is unrecognized, and PII redaction in all logged or instrumented output.
- `subscribers`: List, retrieve, upsert, batch upsert, segment add/remove, and unsubscribe — including `BatchResult` partial-failure semantics.
- `segments`: List, create, retrieve, and list colors.
- `custom-fields`: List (paginated), create, and list all.
- `workflows`: List (with the `perPage` and `statuses` parameter quirks) and subscriber add/remove.
- `webhooks-management`: CRUD over webhook registrations.
- `campaigns`: List campaigns with the PascalCase filter parameters, publish a Canva email, and read Canva design state.
- `pagination`: One `page`/`per_page` interface across all list endpoints, normalizing the upstream naming inconsistencies, plus the traversal strategy and its rate-limit implications.
- `value-objects`: Response object construction, the `#to_h` raw-payload escape hatch, and enum handling for `status` and `source`.
- `rails-integration`: Install generator, Railtie, `ActiveSupport::Notifications` events, and test helpers.
- `webhook-handling`: Parsing the three inbound events, mandatory verification (token-in-path or re-fetch), and the composed dedupe key given that events carry no unique id.

### Modified Capabilities

None. `openspec/specs/` is empty; this is the project's first change.

## Impact

**Affected code** — the entire `lib/` tree. The existing skeleton (`lib/flodesk/rb.rb`, `lib/flodesk/rb/version.rb`, `sig/flodesk/rb.rbs`, `spec/flodesk/rb_spec.rb`) is replaced by a `Flodesk`-namespaced layout. `flodesk-rb.gemspec` needs its TODO placeholders filled and `required_ruby_version` held at `>= 3.2.0` (required for `Data.define`).

**Dependencies** — no runtime dependencies added. Development dependencies: `rspec`, `webmock`, `rubocop`. Rails integration is loaded conditionally and never hard-depends on Rails.

**External constraints the gem cannot change**
- Rate limits: 100 req/min default, 20 req/min for `POST /subscribers/batch` (≤50 subscribers each, so a 1,000 upserts/min ceiling).
- `X-Fd-RateLimit-Limit` and `X-Fd-RateLimit-Remaining` are returned, but there is **no reset header**, so any backoff interval is a documented guess rather than a computed one.
- `custom_fields` values are typed `string` only; non-string values must be coerced or they are rejected.
- Caps: 50 segments per subscriber, 50 subscribers per batch request.
- Webhook payloads embed `email` and `optin_ip`, and the token-in-path verification option puts a secret in a URL that Rails logs — both require log filtering guidance in the install docs.

**Non-goals**
- OAuth2 / partner integrations. The flow needs token storage, expiry, and single-use refresh-token rotation whose concurrent-refresh race requires locking — a subsystem, not a feature. The transport layer will keep an auth strategy seam so it can be added later without a breaking change.
- ActiveRecord-style persistence (`save!`, dirty tracking, lazy associations). `POST /subscribers` is an upsert returning `200` and never reports whether a record was created or updated, so create-vs-update semantics cannot be honored.
- Code generation from the OpenAPI spec. The spec is used as a test oracle instead, keeping the client hand-written and idiomatic.
