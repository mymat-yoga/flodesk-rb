## ADDED Requirements

### Requirement: Error hierarchy

The gem SHALL define a rescuable error hierarchy rooted at `Flodesk::Error` so callers can rescue broadly or narrowly. HTTP status codes MUST map to distinct subclasses: `400` to `Flodesk::BadRequestError`, `401` to `Flodesk::AuthenticationError`, `404` to `Flodesk::NotFoundError`, `429` to `Flodesk::RateLimitError`, and `5xx` to `Flodesk::ServerError`. Transport failures MUST map to `Flodesk::ConnectionError` and `Flodesk::TimeoutError`. Every error class MUST descend from `Flodesk::Error`.

#### Scenario: Unauthorized response

- **WHEN** the API returns `401` with `{"code":"unauthorized","message":"Unauthorized access is denied!"}`
- **THEN** a `Flodesk::AuthenticationError` MUST be raised

#### Scenario: Missing subscriber

- **WHEN** `GET /subscribers/{id_or_email}` returns `404`
- **THEN** a `Flodesk::NotFoundError` MUST be raised

#### Scenario: Rescuing broadly

- **WHEN** a caller rescues `Flodesk::Error`
- **THEN** every error the gem raises MUST be caught, including connection and timeout failures

#### Scenario: Undocumented status code

- **WHEN** the API returns a status with no specific mapping, such as `418`
- **THEN** a generic `Flodesk::Error` MUST be raised rather than allowing an unhandled exception

### Requirement: Error envelope parsing with graceful degradation

Errors SHALL expose `#code` and `#message` parsed from the `{"code": ..., "message": ...}` envelope, plus `#status` and the raw response body. Because the OpenAPI spec declares no error schema, parsing MUST degrade gracefully: an unexpected or unparseable body MUST still produce a typed error carrying the raw response, never a failure on `nil`.

#### Scenario: Well-formed error envelope

- **WHEN** an error response body is `{"code":"invalid_email","message":"Email is invalid"}`
- **THEN** the raised error's `#code` MUST be `"invalid_email"` and `#message` MUST be `"Email is invalid"`

#### Scenario: Error body is empty

- **WHEN** an error response has an empty body
- **THEN** a status-appropriate error MUST still be raised, with `#code` `nil` and a message derived from the status

#### Scenario: Error body is HTML from an edge proxy

- **WHEN** an error response body is HTML rather than JSON
- **THEN** a status-appropriate error MUST be raised carrying the raw body, with no parse exception escaping

#### Scenario: Error body omits expected fields

- **WHEN** an error response body is valid JSON but lacks `code` and `message`
- **THEN** the error MUST be raised with those readers returning `nil` and the raw body retained

### Requirement: Rate limit errors carry observed limit state

`Flodesk::RateLimitError` SHALL expose the observed `X-Fd-RateLimit-Limit` and `X-Fd-RateLimit-Remaining` values, and MUST document that no reset time is available from the API.

#### Scenario: Rate limit exceeded after retries

- **WHEN** `429` responses exhaust the retry budget
- **THEN** a `Flodesk::RateLimitError` MUST be raised exposing the observed limit and remaining values

### Requirement: Partial failure error for batch operations

The gem SHALL define `Flodesk::PartialFailureError` for batch operations where some records fail within a `200` response. It MUST carry the complete `BatchResult`, so successful records remain accessible to the caller and no work is lost by raising.

#### Scenario: Some batch records fail

- **WHEN** `POST /subscribers/batch` returns `200` with two successes and one failure
- **THEN** a `Flodesk::PartialFailureError` MUST be raised whose result exposes both the two successes and the one failure

#### Scenario: PartialFailureError is rescuable as Flodesk::Error

- **WHEN** a caller rescues `Flodesk::Error` around a batch call with failures
- **THEN** the `Flodesk::PartialFailureError` MUST be caught

### Requirement: No PII in error output

Error messages, logs, and instrumentation payloads MUST NOT expose personally identifiable information. `email`, `custom_fields`, and `optin_ip` MUST be redacted from any gem-generated output. Subscriber `id` MAY be used as the loggable handle. Because upstream `message` strings are free-form and may echo a submitted email, error messages MUST be treated as untrusted for logging purposes.

#### Scenario: Instrumented failing request

- **WHEN** a request fails and the gem emits an instrumentation event
- **THEN** the payload MUST NOT contain any email address, custom field value, or opt-in IP

#### Scenario: Upstream message echoes an email

- **WHEN** the API returns a message containing a submitted email address
- **THEN** the gem MUST NOT write that message to a log or instrumentation payload, while still exposing it to the caller on the error object

#### Scenario: Subscriber identified in a log line

- **WHEN** the gem logs a request concerning a specific subscriber
- **THEN** the subscriber `id` MAY appear and the `email` MUST NOT
