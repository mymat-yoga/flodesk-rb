Tasks follow red-green-refactor: each implementation task is preceded by a task writing the failing spec that justifies it. Do not start an implementation task until its spec is confirmed failing for the right reason.

## 1. Project scaffolding

- [x] 1.1 Add `rspec`, `webmock`, and `rubocop` as development dependencies in the Gemfile; configure WebMock to block all real HTTP connections in `spec/spec_helper.rb`
- [x] 1.2 Vendor the upstream `openapi.json` to `spec/fixtures/openapi.json` and record its retrieval date in a sibling README
- [x] 1.3 Rename the namespace: create `lib/flodesk.rb` and `lib/flodesk/version.rb` under module `Flodesk`; delete `lib/flodesk/rb.rb`, `lib/flodesk/rb/version.rb`, `sig/flodesk/rb.rbs`, and `spec/flodesk/rb_spec.rb`
- [x] 1.4 Fill the gemspec TODO placeholders (summary, description, homepage, source and changelog URIs, `allowed_push_host`); confirm `required_ruby_version` stays at `>= 3.2.0` since `Data.define` requires it
- [x] 1.5 Verify `bundle exec rspec` and `bundle exec rubocop` both run green on the empty suite

## 2. Errors

- [x] 2.1 Write failing specs for the error hierarchy: every class descends from `Flodesk::Error`; `400`/`401`/`404`/`429`/`5xx` map to their subclasses; an undocumented status yields a generic `Flodesk::Error`
- [x] 2.2 Implement the error hierarchy including `ConnectionError`, `TimeoutError`, and `PartialFailureError`
- [x] 2.3 Write failing specs for envelope parsing and graceful degradation: well-formed `{code,message}`; empty body; HTML body; valid JSON missing both fields
- [x] 2.4 Implement envelope parsing exposing `#code`, `#message`, `#status`, and the raw body, never raising on unexpected shapes
- [x] 2.5 Write failing specs asserting `RateLimitError` exposes observed limit and remaining values; implement

## 3. HTTP transport

- [x] 3.1 Write failing specs for client construction: `api_key` required, config frozen, `base_url` overridable, two clients isolated
- [x] 3.2 Implement `Flodesk::Client` with frozen config and no global state
- [x] 3.3 Write failing specs for authentication and `User-Agent`: Basic header encodes `"<api_key>:"`; UA contains `app_name` when given and always the gem name and version
- [x] 3.4 Implement the auth strategy seam (Basic only) and UA construction
- [x] 3.5 Write failing specs for JSON transport: JSON body with correct content type; `204` not parsed; unparseable 2xx body raises carrying the raw body
- [x] 3.6 Implement the `Net::HTTP` request cycle with a fresh connection per request and configurable connect and read timeouts
- [x] 3.7 Write failing specs for the per-endpoint idempotency flag: idempotent operations retry on `5xx`; non-idempotent operations do not; retry safety is never inferred from the HTTP verb
- [x] 3.8 Implement retry and backoff: always retry `429`; retry `5xx`, timeouts, and connection resets only when idempotent; never retry other `4xx`; exponential backoff with jitter capped at 60 seconds; retries configurable and disableable
- [x] 3.9 Write failing specs asserting rate-limit headers are exposed after a call and are `nil` when absent; implement
- [x] 3.10 Write a failing thread-safety spec exercising one client concurrently from many threads; confirm no shared mutable state

## 4. Value objects

- [x] 4.1 Write failing specs for immutability, method-based attribute access, `NoMethodError` on unknown attributes, and value equality
- [x] 4.2 Implement the `Data.define` value objects: `Subscriber`, `Segment`, `CustomField`, `Workflow`, `Webhook`, `Campaign`, `BatchResult`, `BatchItemError`
- [x] 4.3 Write failing specs for the `#to_h` escape hatch: undeclared response fields are preserved and reachable; missing optional fields read as `nil`; payloads round-trip
- [x] 4.4 Implement raw payload retention on every value object
- [x] 4.5 Write failing specs for enum coercion: known `status` and `source` values become symbols; unknown values pass through without raising; absent values read as `nil`
- [x] 4.6 Implement enum coercion with pass-through
- [x] 4.7 Write failing specs for timestamp coercion: valid ISO 8601 becomes `Time`; absent reads `nil`; unparseable passes through without raising
- [x] 4.8 Implement timestamp coercion
- [x] 4.9 Write failing specs for nested construction: `segments` becomes an array of `Segment`, empty when absent; `custom_fields` is a string-to-string hash
- [x] 4.10 Implement nested object construction

## 5. Pagination

- [x] 5.1 Write failing specs for the uniform interface: subscribers send `per_page`, workflows send `perPage`, both from the same caller-facing arguments; omitting arguments sends no pagination params
- [x] 5.2 Implement per-endpoint pagination parameter translation
- [x] 5.3 Write failing specs for `per_page` bounds: above 100 and below 1 raise `ArgumentError` with no HTTP request; exactly 100 succeeds
- [x] 5.4 Implement bounds validation
- [x] 5.5 Write failing specs for `Page`: exposes `page`, `per_page`, `total_pages`, `total_items`; `Enumerable` over items; `#to_h`; empty `data`; absent `meta`; reports whether a further page exists
- [x] 5.6 Implement `Flodesk::Page`
- [x] 5.7 Write failing specs for `auto_paging_each`: traverses all pages in order; lazy enough that taking one item fetches one page; honors `per_page`; propagates mid-traversal errors; `list` itself issues exactly one request
- [x] 5.8 Implement opt-in `auto_paging_each`
- [x] 5.9 Write failing specs for filter translation, including campaigns' PascalCase parameters and rejection of out-of-enum filter values; implement

## 6. Subscribers

- [x] 6.1 Write failing specs for list: plain list; `status` filter; `segment_id` filter
- [x] 6.2 Implement the subscribers list operation
- [x] 6.3 Write failing specs for retrieve: by id; by email; email containing `+` correctly encoded; `404` raises `NotFoundError`
- [x] 6.4 Implement retrieve with path encoding
- [x] 6.5 Write failing specs for upsert: create and update both return a `Subscriber`; neither `id` nor `email` raises `ArgumentError`; `segment_ids` sent; more than 50 segment ids raises; `double_optin` sent; `503` is retried
- [x] 6.6 Implement upsert, declared idempotent, documenting that create-versus-update cannot be distinguished
- [x] 6.7 Write failing specs for batch upsert: all-success returns `BatchResult` with `#success?` true; any failure raises `PartialFailureError` by default; `raise_on_failure: false` returns quietly; failures expose `index`, `email`, `id`, `code`, `message`; successes survive the raise; more than 50 records raises; empty array raises
- [x] 6.8 Implement batch upsert with `BatchResult` and default-raise semantics
- [x] 6.9 Write failing specs for segment add and remove, including the no-op cases and `404`; implement both, declared idempotent
- [x] 6.10 Write failing specs for unsubscribe including the already-unsubscribed case; implement, declared idempotent
- [x] 6.11 Resolve the open question on non-string custom field values (coerce or raise), then write failing specs for the chosen rule and implement it consistently across every write path — **resolved: coerce.** The API accepts only strings, so coercion cannot lose information and is friendlier than raising; `nil` is preserved because it means "clear this field", which differs from `""`

## 7. Segments, custom fields, workflows

- [x] 7.1 Write failing specs for segments list, retrieve, and colors, including empty results and the `401` documented for colors; implement
- [x] 7.2 Write failing specs for segment create: returns the created `Segment`; `503` and timeouts are **not** retried; `400` raises without retry
- [x] 7.3 Implement segment create, declared non-idempotent
- [x] 7.4 Write failing specs for custom fields list and list-all, asserting list-all sends no pagination parameters; implement both
- [x] 7.5 Write failing specs for custom field create asserting no retry on `503` or timeout; implement, declared non-idempotent
- [x] 7.6 Write failing specs for workflows list asserting `perPage` is sent and `per_page` is not, plus `statuses` serialization and the documented `404`; implement — **note:** `statuses` is comma-separated (`statuses=active,paused`) per the parameter description, not repeated keys as the bare `type: array` schema implies; it also has its own closed enum (`active`/`paused`/`draft`), distinct from both the subscriber and campaign status enums
- [x] 7.7 Write failing specs for workflow subscriber add and remove: `204` responses are not parsed as JSON; email paths encoded; `404` and `400` mapped; `503` retried
- [x] 7.8 Implement workflow subscriber add and remove, declared idempotent

## 8. Webhook management and campaigns

- [x] 8.1 Write failing specs for webhook list, retrieve, and update, including the `503` retry permitted for `PUT`; implement
- [x] 8.2 Write failing specs for webhook create: unknown event names raise `ArgumentError` before any request; `503` is not retried; implement, declared non-idempotent — **note:** the API also requires a `name` field, which the scraped docs omitted
- [x] 8.3 Write failing specs for webhook delete asserting the `204` body is not parsed; implement, declared idempotent
- [x] 8.4 Write failing specs for campaigns list asserting `Search`, `OrderBy`, `Sort`, `Status`, and `SharedAsTemplate` are sent in PascalCase while `page` and `per_page` stay snake_case, and that out-of-enum statuses raise
- [x] 8.5 Implement the campaigns list operation
- [x] 8.6 Write failing specs for Canva publish asserting it is **never** retried on `5xx`, timeout, or `429`, and returns the campaign from `201`
- [x] 8.7 Implement Canva publish, declared non-idempotent, with an explicit code comment recording that a retry could send the campaign to the whole list twice
- [x] 8.8 Write failing specs for Canva design state retrieval including `404`; implement

## 9. Webhook handling

- [x] 9.1 Write failing specs asserting a handler constructed without a verification strategy raises, and that re-fetch without a client raises
- [x] 9.2 Implement the handler with mandatory strategy selection
- [x] 9.3 Write failing specs for token-in-path: matching token accepted; mismatched and absent tokens rejected unparsed; comparison is constant-time; token generator returns a cryptographically random value
- [x] 9.4 Implement token-in-path verification using a constant-time comparison
- [x] 9.5 Write failing specs for re-fetch: dispatches the re-fetched subscriber, not the payload copy; `404` on re-fetch treats the event as unverified; only the identifier is taken from the payload
- [x] 9.6 Implement re-fetch verification
- [x] 9.7 Write failing specs for event parsing: all three events; `subscriber.added_to_segment` exposes its segment; unknown event names do not raise and remain reachable via `#to_h`; malformed JSON rejected without dispatch
- [x] 9.8 Implement event parsing
- [x] 9.9 Write failing specs for the composed dedupe key: stable for identical deliveries, distinct across different events; implement — hashed with SHA-256 so the value applications persist carries no raw email or IP
- [x] 9.10 Write failing specs for response semantics: verified and dispatched returns 2XX; verification failure returns non-2XX; an exception from the application handler returns non-2XX; implement

## 10. Rails integration

- [x] 10.1 Write a failing spec asserting the gem loads and functions with `Rails` undefined and references no Rails constant; implement conditional loading
- [x] 10.2 Write failing specs for the Railtie loading under Rails; implement
- [x] 10.3 Write failing generator specs: creates `config/initializers/flodesk.rb` wired to credentials and assigning a constant; includes `app_name`; refuses to overwrite an existing file; writes no API key into the repo — the generator refuses explicitly rather than relying on Thor's collision prompt, which resolves to *overwrite* on a non-interactive shell; `--force` opts in
- [x] 10.4 Implement `rails g flodesk:install`
- [x] 10.5 Write failing specs for `flodesk.request` instrumentation: emitted on success and failure; carries method, endpoint, status, duration, attempts, and rate-limit remaining; contains no email, custom field values, or opt-in IP; an email in a URL path is redacted; no instrumentation attempted when ActiveSupport is absent — **bug caught:** redaction matched only a literal `@`, but instrumentation sees the already-encoded path, so `a%40b.com` was leaking emails into notification payloads
- [x] 10.6 Implement instrumentation with PII redaction
- [x] 10.7 Write failing specs for the test helpers: stub a successful upsert, a `404`, and a partial batch failure; assert nothing is loaded when only the main entry point is required
- [x] 10.8 Implement opt-in test helpers with spec-derived fixture payloads

## 11. Contract verification

- [x] 11.1 Write the contract spec that walks `spec/fixtures/openapi.json` and asserts a resource method exists for each of the 25 `operationId`s
- [x] 11.2 Extend it to assert every declared query parameter is actually sent, including `perPage` and the PascalCase campaign filters
- [x] 11.3 Extend it to assert each value object covers its schema's declared properties
- [x] 11.4 Extend it to assert every documented status code maps to a known error class
- [x] 11.5 Confirm the contract spec fails when an operation is removed from a resource, proving it detects drift rather than passing vacuously — verified against four independent drift injections: a new upstream operation, a removed client method, a shortened enum, and a dropped value-object member. All four failed; the fixture SHA-256 was confirmed unchanged afterwards

## 12. Documentation and release readiness

- [x] 12.1 Write RBS signatures under `sig/` covering value objects, resource methods, and error classes; confirm validation passes — `rbs validate` exits 0 even when reporting errors, so `signatures_spec.rb` inspects its output and cross-checks that every value-object member has a declared `attr_reader`
- [x] 12.2 Rewrite the README: installation, client construction, per-resource examples, and a rate-limit section stating that no reset header exists and the gem makes no quota guarantee
- [x] 12.3 Document webhooks prominently: no signing exists, verification is mandatory, both strategies with their trade-offs, log filtering for the callback path, and that replay protection is the application's responsibility
- [x] 12.4 Document the maturity caveat on the Canva endpoints and the create-versus-update limitation of subscriber upsert
- [x] 12.5 Walk the path twice on stateful and repeat flows: `auto_paging_each` run twice over the same collection; retry then success then retry again on one client; batch with all-success followed by partial-failure on the same client; webhook handler processing the same event twice; empty and `nil` arguments to every list and write operation — **bug caught:** `.from` froze the caller's hash (and left nested data mutable); now copies via `Coercion.snapshot`
- [x] 12.6 Resolve or explicitly defer each remaining design open question (cap enforcement and batch auto-chunking, `Page#next_page`, campaign `Status` symbol coercion, backoff ceiling), recording the outcome in `design.md` — all five resolved, plus a "Discovered During Implementation" section recording the nine facts that changed the design
- [x] 12.7 Update `CHANGELOG.md` for `0.1.0`, noting the public surface is unstable until exercised against a live account
- [x] 12.8 Run the full suite plus RuboCop green, and confirm no PII appears anywhere in test output — 506 examples green, RuboCop clean, RBS clean, gem builds; `pii_spec.rb` now enforces containment permanently rather than by one-off inspection
