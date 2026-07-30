## Context

The repository is a bare `bundle gem flodesk-rb` skeleton — `Flodesk::Rb` with a placeholder `Error` class, an empty RBS sig, and a stub spec. Nothing has been released to RubyGems, and no `flodesk` gem exists there, so this is greenfield with no backward-compatibility obligations.

Design decisions are grounded in the upstream `openapi.json` (OpenAPI 3.0.3, 18 paths, 25 operations, 24 schemas, plus 3 inbound webhook events declared under `x-webhooks`) plus direct probing of the live API. Facts established:

| Property | Value |
| --- | --- |
| Base URL | `https://api.flodesk.com/v1` |
| Auth | HTTP Basic, API key as username, empty password. Also OAuth2 authorization-code (out of scope) |
| Error envelope | `{"code":"unauthorized","message":"Unauthorized access is denied!"}` — verified live; **the spec itself declares no error schema** |
| Pagination | `page` / `per_page`, default 20, max 100. `GET /workflows` uses `perPage`. `GET /campaigns` uses PascalCase filters |
| Rate limits | 100 req/min default; 20 req/min for `POST /subscribers/batch` |
| Rate-limit headers | `X-Fd-RateLimit-Limit`, `X-Fd-RateLimit-Remaining` — **no reset header** |
| `User-Agent` | Every documented example sends an app-identifying UA |
| Batch | `200 OK` with both `successes[]` and `failures[]` |
| Webhook events | 3 events, each declaring `security: []`, no unique event id |
| Enums | `status` (6 values), `source` (5 values), campaign `Status` (7 values) |
| `custom_fields` | `additionalProperties: {type: string}` — string values only |

Ruby 3.2.0 is the floor (already in the gemspec), which makes `Data.define` available.

## Goals / Non-Goals

**Goals:**

- Cover all 25 operations with an idiomatic, hand-written Ruby surface.
- Hide the API's naming inconsistencies behind one uniform interface.
- Make the two silent-data-loss hazards — batch partial failure and unsafe POST retries — impossible to hit by accident.
- Zero runtime dependencies, so the gem never forces a version negotiation on a host Rails app.
- Thread-safe clients suitable for assignment to a constant under Puma.
- Machine-checkable completeness: the vendored OpenAPI spec fails the build when coverage drifts.
- Never emit PII in logs or instrumentation.

**Non-Goals:**

- OAuth2 / partner integrations (an auth seam is preserved; the flow is not built).
- ActiveRecord-style persistence, dirty tracking, or lazy-loaded associations.
- Code generation from the OpenAPI spec.
- Client-side rate limiting that guarantees staying under the quota — impossible without a reset header.
- Connection pooling or persistent HTTP connections in v1.

## Decisions

### 1. Namespace `Flodesk`, not `Flodesk::Rb`

`bundle gem flodesk-rb` generated `Flodesk::Rb`, leaking the packaging suffix into the public API. The RubyGems package name stays `flodesk-rb`; the Ruby module becomes `Flodesk`.

*Alternative considered:* keep `Flodesk::Rb`. Rejected — `Flodesk::Rb::Client.new` reads badly, and the rename is free before release and breaking after.

### 2. `Net::HTTP`, zero runtime dependencies

*Alternative considered:* Faraday, which is more ergonomic internally and gives middleware for free. Rejected because a gem intended to drop into arbitrary Rails apps should not participate in Faraday major-version conflicts. The API surface used here is small enough that stdlib is sufficient.

### 3. Immutable `Data.define` value objects with a mandatory `#to_h` escape hatch

Responses become typed objects (`sub.email`, `sub.status`) rather than raw hashes, so typos raise `NoMethodError` instead of returning `nil`, and RBS signatures are meaningful.

Every object also carries `#to_h` returning the raw parsed payload. This is the critical safety valve for a third-party API: when Flodesk ships a field, callers reach it via `sub.to_h["new_field"]` immediately rather than waiting on a gem release. Unknown fields are never dropped and never raise.

*Alternatives considered:* plain hashes (thin, nothing to maintain, but silent `nil` on typos and no useful type signatures); ActiveRecord-like models (rejected — `POST /subscribers` is an upsert returning `200` that never reports create-vs-update, so `save!` semantics would be fiction, and lazy associations would hide N+1 HTTP calls).

### 4. Enum values become symbols, unknown values pass through

`status` and `source` are closed enums. Known values are exposed as symbols (`:active`); an unrecognized value is passed through unchanged rather than raising, so a new Flodesk status cannot break existing callers.

### 5. `BatchResult`, raising by default

`POST /subscribers/batch` is the only operation where success and failure share a `200`. It returns a `BatchResult` exposing `#success?`, `#successes`, `#failures`, and `#to_h`, and `batch_upsert` raises `Flodesk::PartialFailureError` — carrying the full result, so successes are never lost — when any record failed. `raise_on_failure: false` returns the object quietly.

*Alternatives considered:* never raise (rejected — silent subscriber loss becomes the default behavior, and it is the one bug a green test suite hides); a separate `batch_upsert!` (rejected — the shorter, unsuffixed name would be the unsafe one).

### 6. Per-endpoint idempotency flags drive retries

Retry safety here is a property of the endpoint, not the HTTP verb:

```
safe to retry                          NOT safe to retry
─────────────────────────────          ─────────────────────────────
POST /subscribers          upsert      POST /segments        creates
POST /subscribers/batch    upsert      POST /custom-fields   creates
POST .../segments          add         POST /webhooks        creates
POST .../unsubscribe       set         POST /campaigns/canva PUBLISHES
POST /workflows/.../subscribers        ↳ retry can send a campaign twice
DELETE (all)               idempotent
```

Each resource method declares `idempotent: true|false`; the transport reads that flag. Blanket "retry all POSTs" creates duplicate segments and can publish a campaign to the whole list more than once. Blanket "never retry POST" abandons retries on the hot path, since subscriber upsert is a POST and dominates real traffic.

Policy: `429` always retries with exponential backoff plus jitter. `5xx`, timeouts, and connection resets retry only when the endpoint is flagged idempotent. Other `4xx` never retry.

### 7. Backoff intervals are a documented guess

With `X-Fd-RateLimit-Remaining` but no reset header, no correct wait time is computable. The gem uses exponential backoff with jitter capped at the 60-second window length, documents this as a heuristic, and surfaces `Remaining` on every response so callers can self-pace. The gem explicitly does not promise to keep callers under quota.

### 8. Explicit clients, no global mutable state

`Flodesk::Client.new(api_key:, app_name:, ...)` only. No `Flodesk.configure`. Per-tenant keys are then trivial, and there is no process-wide state to leak between tests.

Consequence: a client assigned to a constant is shared across Puma threads, so config is frozen at construction and each request opens its own `Net::HTTP` connection. Pooling is deferred.

The Rails generator scaffolds the singleton in the *host app* rather than in the gem:

```ruby
# config/initializers/flodesk.rb
FLODESK = Flodesk::Client.new(
  api_key:  Rails.application.credentials.flodesk_api_key,
  app_name: "MyApp (myapp.com)"
)
```

### 9. Mandatory webhook verification

The spec declares `security: []` on all three events — no signature exists, so any party who learns the callback URL can forge events. Two workable strategies:

- **Token in URL path** — a random token compared with `secure_compare`. Cheap, no API call. Downside: the secret appears in server access logs and Rails request logs, so the install docs must cover log filtering.
- **Re-fetch** — treat the payload as an untrusted hint, take `subscriber.id`, and `GET /subscribers/{id}` for authoritative data. Forgery-proof, costs one call against the 100/min budget.

IP allowlisting is not viable; Flodesk publishes no ranges.

Constructing a handler without selecting a strategy **raises**. Defaulting to "accept anything" would make every installing app vulnerable.

### 10. Webhook dedupe key is composed and exposed, not enforced

Events carry `event_name`, `event_time`, `subscriber`, `webhook_id` — no unique event id. The gem exposes a composed key (`webhook_id` + `event_name` + `subscriber.id` + `event_time`) and leaves idempotent storage to the app, which is the only layer with a database.

### 11. PII redaction by default

Error `message` strings are free-form and may echo submitted values (`"invalid email: foo@bar.com"`). Webhook payloads embed `email` and `optin_ip`. All instrumentation and logging redacts `email`, `custom_fields`, and `optin_ip` by default, using subscriber `id` as the loggable handle.

### 12. The OpenAPI spec is a test oracle, not a generator input

`openapi.json` is vendored under `spec/fixtures/`. A contract spec walks it and asserts every `operationId` has a resource method, declared query params are actually sent, value objects cover their schema properties, and every documented status code maps to a known error class. Dropping in a newer spec fails the build when Flodesk adds an endpoint.

*Alternative considered:* generating the client. Rejected — generated Ruby is nobody's idea of idiomatic, and regeneration clobbers hand-tuning. Using the spec as an oracle keeps hand-written code and still detects drift.

### 13. Explicit pagination, with opt-in auto-paging

`list` returns a `Page` (items plus `page`/`per_page`/`total_pages`/`total_items` from `meta`). A separate `auto_paging_each` returns a lazy `Enumerator`.

Auto-paging is not the default because a single `each` over a large list can silently consume the entire 100/min budget; making traversal explicit keeps that cost visible. One `page:`/`per_page:` interface is presented regardless of whether the endpoint underneath wants `per_page`, `perPage`, or PascalCase filters.

### Architecture

```
Flodesk::Client.new(api_key:, app_name:)
            │  frozen config, thread-safe
            ▼
   Flodesk::Connection            (Net::HTTP, no deps)
     · Basic auth (key : "")      · retry ← per-endpoint idempotency flag
     · User-Agent                 · reads X-Fd-RateLimit-*
     · JSON encode/decode         · {code,message} → Error subclass
     · AS::Notifications (PII redacted)
            │
  ┌─────────┼──────────┬──────────────┬───────────┬───────────┐
subscribers segments custom_fields workflows  webhooks  campaigns
            │
     Pagination — normalizes per_page / perPage / PascalCase
            │
            ▼
   Objects (Data.define, immutable, all expose #to_h)
     Subscriber Segment CustomField Workflow Webhook Campaign
     Page  BatchResult  BatchItemError

   Rails (loaded only when Rails is present)
     Railtie · install generator · webhook handler · test helpers
```

## Risks / Trade-offs

- **Webhooks are forgeable by design** → Verification is mandatory at construction; both viable strategies shipped; re-fetch documented as the stronger one.
- **Token-in-path puts a secret in Rails logs** → Install docs cover log filtering for the webhook route; re-fetch offered as the alternative that needs no URL secret.
- **Retrying `POST /campaigns/canva` could publish a campaign twice** → Flagged non-idempotent, never retried, with an explicit code comment. This is the highest-consequence failure mode in the gem.
- **Backoff on 429 is guesswork without a reset header** → Documented as heuristic; `Remaining` surfaced so callers can self-pace; no quota guarantee promised.
- **Value objects need updating when Flodesk adds fields** → `#to_h` on every object makes this a mild inconvenience rather than a hard block; the contract spec detects it.
- **The error envelope is reverse-engineered, not specified** → Parsing degrades gracefully: an unrecognized body still raises a typed error carrying the raw response rather than failing on `nil`.
- **Zero dependencies means reimplementing retry, backoff, and JSON handling** → Accepted; the scope is small and dependency-conflict-free installation is worth more to a host Rails app.
- **No global config may feel verbose in single-tenant apps** → The generator scaffolds a host-app constant, giving the same ergonomics without gem-level state.
- **25 operations is a broad v1 surface to test** → The contract spec makes coverage verifiable rather than assumed, and thin resource methods over one transport keep the per-endpoint cost low.
- **Campaigns/Canva endpoints are niche and hard to exercise** → Covered against spec-derived stubs; documented as less battle-tested than subscribers and segments.

## Migration Plan

No consumers exist, so there is nothing to migrate. Sequence:

1. Replace the skeleton: `lib/flodesk.rb` plus the `Flodesk` tree; delete `lib/flodesk/rb.rb`, `sig/flodesk/rb.rbs`, `spec/flodesk/rb_spec.rb`.
2. Fill the gemspec TODOs; hold `required_ruby_version >= 3.2.0`.
3. Build transport and errors first — every resource depends on them.
4. Add resources in traffic order: subscribers, segments, custom fields, workflows, webhooks, campaigns.
5. Layer Rails integration behind a `defined?(Rails)` guard.
6. Vendor `openapi.json` and add the contract spec.
7. Release `0.1.x` with the public surface marked unstable until the API has been exercised against a real account.

Rollback is `gem uninstall` / reverting the branch; there is no persistent state or migration to undo.

## Open Questions

All resolved during implementation. Recorded here rather than deleted, since the reasoning is the useful part.

### Resolved: coerce non-string `custom_fields` values

**Coerce.** `42` becomes `"42"`, `true` becomes `"true"`. The API types these values as `string` only, so coercion cannot lose information — the alternative was rejecting a payload the caller plainly intended. `nil` is deliberately preserved rather than becoming `""`, because it means "clear this field", which is a different instruction. Applied on every write path that accepts custom fields, including each record of a batch.

### Resolved: enforce documented caps client-side; do not auto-chunk

**Enforce, don't chunk.** `per_page > 100`, more than 50 segments per subscriber, and more than 50 records per batch all raise `ArgumentError` before any HTTP request. Failing locally is faster and clearer than a round trip to a rejection.

Auto-chunking was rejected. It reads as a convenience but changes the operation's semantics in three ways the caller cannot see: one call becomes N requests against a 20/minute limit, partial failure has to be merged across chunks with `index` values that no longer refer to the caller's array, and a mid-sequence failure leaves the batch half-applied with no clean way to report it. Chunking is a policy decision belonging to the caller, who knows their own pacing and error handling. `BatchResult#failed_emails` makes assembling the next batch straightforward.

### Resolved: no `Page#next_page`

`Page#more_pages?` reports whether another page exists, and `auto_paging_each` traverses. A third mechanism would be a redundant way to spend rate-limit budget, and `#next_page` invites a manual `while` loop that duplicates what `auto_paging_each` already does correctly and lazily.

### Resolved: yes, coerce campaign `Status` to a symbol

`CampaignItem.status` is a documented closed enum exactly like `SubscriberRes.status`, so it is exposed as a symbol for consistency. The PascalCase spelling is a property of the *request* parameter, not of the response value, and callers should not have to track which enums got symbol treatment.

While resolving this, a third status enum surfaced: `GET /workflows`'s `statuses` filter has its own set (`active`/`paused`/`draft`), distinct from both the subscriber and campaign enums. All three now live in `Flodesk::Enums` and are contract-verified against `openapi.json`.

### Resolved: keep the 60-second backoff cap

Kept, because it equals the rate-limit window and is therefore the only interval with any principled justification available — with no reset header, a shorter cap would be an arbitrary guess dressed up as a smaller one. What actually protects a request/response cycle is the retry *count* (default 2) and the finite read timeout, both configurable, with `max_retries: 0` disabling retries outright. A web request never waits 60 seconds at the default settings; a background job may, which is the right place for it.

## Discovered During Implementation

Facts not visible at design time that changed the implementation:

- **`GET /workflows`'s `statuses` filter is comma-separated**, not repeated keys. The machine-readable schema said only `type: array`, from which the OpenAPI default implies `?statuses=a&statuses=b`; the correct form was in the parameter's prose `description` (`statuses=active,paused`). Schema types alone under-specify array serialization.
- **`POST /webhooks` requires a `name` field** that the scraped documentation omitted entirely.
- **Request bodies are declared under `*/*`**, not `application/json` — a codegen artifact that hides them from a naive query.
- **`CustomFieldRes` is `key`/`label`**, with no id or name; **`WorkflowRes` declares only `id`/`name`**, with no status field despite the list endpoint filtering on status.
- **Constants inside a `Data.define do ... end` block bind to the enclosing lexical scope**, not the class. `STATUSES` written in both the Subscriber and Campaign blocks silently defined and then clobbered a single `Flodesk::STATUSES`, leaving subscriber status coercion validating against the campaign enum. Hence `Flodesk::Enums`.
- **Redaction has to run on the encoded path.** Checking for a literal `"@"` missed `a%40b.com`, so emails were reaching instrumentation payloads. The guard and the encoder had to agree on ordering.
- **`.from` must copy, not freeze in place.** Freezing the argument of a public constructor is a side effect on data the caller still owns; `Coercion.snapshot` copies recursively instead, which also stopped a caller mutating nested data underneath a supposedly immutable object.
- **Retry safety cannot be inferred from the verb, but neither can it be ignored.** Defaulting `idempotent: false` for every method honored the rule literally and made plain `GET`s non-retryable. The rule's real scope is that **POST** must never be *assumed* safe.
- **`rbs validate` exits 0 even when it reports errors**, so the signature spec inspects its output rather than its status.
