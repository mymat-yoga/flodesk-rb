## ADDED Requirements

### Requirement: Client construction and immutability

The gem SHALL expose `Flodesk::Client.new(api_key:, app_name:, **options)` as the only way to obtain a client. There SHALL be no gem-level global mutable configuration. Client configuration MUST be frozen at construction so a single client is safe to share across threads.

#### Scenario: Client constructed with an API key

- **WHEN** a caller invokes `Flodesk::Client.new(api_key: "fd_key", app_name: "MyApp (myapp.com)")`
- **THEN** the client is returned ready for use and its configuration is frozen

#### Scenario: API key omitted

- **WHEN** a caller invokes `Flodesk::Client.new` without an `api_key`
- **THEN** an `ArgumentError` MUST be raised at construction time rather than on the first request

#### Scenario: Two clients with different keys used concurrently

- **WHEN** two clients are constructed with different API keys and used from separate threads
- **THEN** each request MUST use its own client's credentials with no cross-contamination

#### Scenario: Shared client used from multiple threads

- **WHEN** one client is assigned to a constant and used concurrently from many threads
- **THEN** each request MUST open its own connection and no shared mutable state may be observed

### Requirement: Authentication

The transport SHALL authenticate with HTTP Basic, sending the API key as the username and an empty string as the password. The auth mechanism MUST be isolated behind a strategy seam so bearer-token auth can be added later without changing the transport's public interface.

#### Scenario: Request is authenticated

- **WHEN** any API request is issued
- **THEN** the request MUST carry an `Authorization: Basic` header encoding `"<api_key>:"`

#### Scenario: API key is never logged

- **WHEN** a request is instrumented or logged
- **THEN** the `Authorization` header value MUST NOT appear in any output

### Requirement: Request identification

The transport SHALL send a `User-Agent` header identifying the calling application, as every documented Flodesk example does. When `app_name` is supplied it MUST be included; the gem name and version MUST always be included.

#### Scenario: app_name supplied

- **WHEN** a client is constructed with `app_name: "MyApp (myapp.com)"`
- **THEN** the `User-Agent` header MUST contain both `"MyApp (myapp.com)"` and the gem name and version

#### Scenario: app_name omitted

- **WHEN** a client is constructed without `app_name`
- **THEN** the `User-Agent` header MUST still identify the gem and version

### Requirement: JSON transport

All requests SHALL target `https://api.flodesk.com/v1`, send `Content-Type: application/json` with JSON-serialized bodies, and parse JSON responses. Responses with status `204` MUST NOT be parsed as JSON.

#### Scenario: Request with a body

- **WHEN** a resource method sends parameters
- **THEN** they MUST be JSON-serialized into the request body with `Content-Type: application/json`

#### Scenario: 204 No Content response

- **WHEN** an endpoint such as `DELETE /webhooks/{id}` returns `204`
- **THEN** the method MUST return without attempting to parse a body

#### Scenario: Response body is not valid JSON

- **WHEN** a 2xx response contains a body that cannot be parsed as JSON
- **THEN** a `Flodesk::Error` MUST be raised carrying the raw response body

#### Scenario: Base URL is overridable for tests

- **WHEN** a client is constructed with an explicit `base_url`
- **THEN** all requests MUST target that URL instead of the production default

### Requirement: Per-endpoint idempotency declaration

Every resource operation SHALL declare whether it is idempotent. The transport MUST read that declaration to decide retry eligibility and MUST NOT infer retry safety from the HTTP method. Operations that create records or publish content MUST be declared non-idempotent.

#### Scenario: Idempotent upsert is retried

- **WHEN** `POST /subscribers` fails with a `503`
- **THEN** the request MUST be retried, because subscriber upsert is declared idempotent

#### Scenario: Segment creation is not retried

- **WHEN** `POST /segments` fails with a `503`
- **THEN** the request MUST NOT be retried, to avoid creating a duplicate segment

#### Scenario: Canva publish is not retried

- **WHEN** `POST /campaigns/canva` fails with a `5xx` or times out
- **THEN** the request MUST NOT be retried, because a retry could publish the campaign to the entire list a second time

#### Scenario: Deletes are retried

- **WHEN** any `DELETE` request fails with a `5xx`
- **THEN** the request MUST be retried, because deletes are idempotent

### Requirement: Retry and backoff policy

The transport SHALL retry `429` responses regardless of idempotency, and SHALL retry `5xx` responses, timeouts, and connection resets only for idempotent operations. Other `4xx` responses MUST NOT be retried. Backoff MUST be exponential with jitter, capped at the 60-second rate-limit window. Retry count MUST be configurable, including disabling retries entirely.

#### Scenario: Rate limited request

- **WHEN** a request receives `429`
- **THEN** the transport MUST wait with exponential backoff plus jitter and retry, up to the configured attempt limit

#### Scenario: Validation error is not retried

- **WHEN** a request receives `400`
- **THEN** the transport MUST raise immediately without retrying, because the payload cannot succeed on retry

#### Scenario: Retries exhausted

- **WHEN** every permitted retry attempt fails
- **THEN** the error from the final attempt MUST be raised, carrying the number of attempts made

#### Scenario: Retries disabled

- **WHEN** a client is constructed with retries set to zero
- **THEN** no request may be retried under any condition

#### Scenario: Backoff never exceeds the window

- **WHEN** backoff is computed for any attempt number
- **THEN** the computed delay MUST NOT exceed 60 seconds

### Requirement: Rate limit visibility

Because Flodesk returns `X-Fd-RateLimit-Limit` and `X-Fd-RateLimit-Remaining` but no reset header, the transport SHALL expose the observed rate-limit state to callers so they can self-pace. The gem MUST NOT claim to keep callers within quota.

#### Scenario: Rate limit headers present

- **WHEN** a response includes `X-Fd-RateLimit-Limit: 100` and `X-Fd-RateLimit-Remaining: 68`
- **THEN** both values MUST be readable by the caller after the call completes

#### Scenario: Rate limit headers absent

- **WHEN** a response omits the rate-limit headers
- **THEN** the exposed values MUST be `nil` and no error may be raised

### Requirement: Timeouts

The transport SHALL apply configurable connect and read timeouts with finite defaults, so a hung Flodesk request cannot block a host application indefinitely.

#### Scenario: Default timeouts applied

- **WHEN** a client is constructed without timeout options
- **THEN** finite connect and read timeouts MUST be applied

#### Scenario: Read timeout exceeded on an idempotent request

- **WHEN** a read timeout elapses during `POST /subscribers`
- **THEN** the request MUST be retried, and a `Flodesk::TimeoutError` raised if retries are exhausted
