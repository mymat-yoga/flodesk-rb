## ADDED Requirements

### Requirement: Verification is mandatory

Because the OpenAPI specification declares `security: []` for all three webhook events, no signature mechanism exists and any party who learns a callback URL can forge events. The gem SHALL therefore require an explicit verification strategy when a webhook handler is constructed, and MUST raise if none is selected. There MUST be no way to accept unverified payloads by default.

#### Scenario: Handler constructed without a strategy

- **WHEN** a developer constructs a webhook handler without selecting a verification strategy
- **THEN** an error MUST be raised at construction time

#### Scenario: Handler constructed with a strategy

- **WHEN** a developer constructs a handler selecting a supported strategy
- **THEN** the handler MUST be returned ready to process events

#### Scenario: Absence of signing is documented

- **WHEN** a developer reads the webhook documentation
- **THEN** it MUST state plainly that Flodesk provides no request signing and that payloads are therefore untrusted

### Requirement: Token-in-path verification

The gem SHALL support verification by a caller-generated secret token embedded in the callback URL path. Comparison MUST use a constant-time method. The gem MUST provide a means of generating a cryptographically random token and MUST document that this secret appears in server access logs and Rails request logs.

#### Scenario: Matching token

- **WHEN** an inbound request carries the registered token
- **THEN** the payload MUST be accepted and parsed

#### Scenario: Mismatched token

- **WHEN** an inbound request carries an incorrect token
- **THEN** the payload MUST be rejected without being parsed or dispatched

#### Scenario: Absent token

- **WHEN** an inbound request carries no token
- **THEN** the payload MUST be rejected

#### Scenario: Comparison is constant-time

- **WHEN** a token is compared against the expected value
- **THEN** the comparison MUST be constant-time, so timing cannot reveal the secret

#### Scenario: Token generation

- **WHEN** a developer requests a token from the gem
- **THEN** a cryptographically random value of sufficient length MUST be returned

#### Scenario: Log exposure is documented

- **WHEN** a developer chooses token-in-path verification
- **THEN** the documentation MUST warn that the token appears in request logs and explain how to filter it

### Requirement: Re-fetch verification

The gem SHALL support treating the payload as an untrusted hint: extracting only the subscriber identifier, then issuing `GET /subscribers/{id}` and using that authoritative response. Documentation MUST record that this strategy is forgery-proof but costs one API call per event against the 100 requests-per-minute budget.

#### Scenario: Payload confirmed by re-fetch

- **WHEN** a handler using re-fetch receives an event and the subscriber is retrieved successfully
- **THEN** the event MUST be dispatched carrying the re-fetched subscriber rather than the payload's copy

#### Scenario: Subscriber not found on re-fetch

- **WHEN** the re-fetch returns `404`
- **THEN** the event MUST be treated as unverified and MUST NOT be dispatched as genuine

#### Scenario: Payload fields other than the identifier are discarded

- **WHEN** a handler using re-fetch receives an event
- **THEN** only the subscriber identifier may be taken from the payload, and all other subscriber data MUST come from the re-fetch

#### Scenario: Re-fetch requires a client

- **WHEN** a handler is constructed with the re-fetch strategy but no client
- **THEN** an error MUST be raised at construction time

### Requirement: Event parsing

The gem SHALL parse the three documented inbound events into value objects exposing `event_name`, `event_time`, `subscriber`, and `webhook_id`, with `subscriber.added_to_segment` additionally exposing `segment`. Parsed events MUST expose `#to_h` returning the raw payload.

#### Scenario: Parsing subscriber.created

- **WHEN** a verified `subscriber.created` payload is received
- **THEN** an event object MUST be returned exposing `event_name`, `event_time`, `webhook_id`, and a `Subscriber`

#### Scenario: Parsing subscriber.added_to_segment

- **WHEN** a verified `subscriber.added_to_segment` payload is received
- **THEN** the event MUST additionally expose the `Segment`

#### Scenario: Parsing subscriber.unsubscribed

- **WHEN** a verified `subscriber.unsubscribed` payload is received
- **THEN** an event object MUST be returned exposing its subscriber

#### Scenario: Unrecognized event name

- **WHEN** a verified payload carries an event name the gem does not know
- **THEN** parsing MUST NOT raise, and the payload MUST remain available via `#to_h` so a newly introduced Flodesk event does not break the handler

#### Scenario: Malformed payload body

- **WHEN** a verified request carries a body that is not valid JSON
- **THEN** the request MUST be rejected without dispatching an event

### Requirement: Composed dedupe key

Because the event schemas define no unique event id, the gem SHALL expose a dedupe key composed of `webhook_id`, `event_name`, the subscriber id, and `event_time`. The gem MUST NOT itself store keys or deduplicate, since only the host application has persistent storage.

#### Scenario: Reading the dedupe key

- **WHEN** a caller reads the dedupe key from a parsed event
- **THEN** a stable value derived from `webhook_id`, `event_name`, subscriber id, and `event_time` MUST be returned

#### Scenario: Duplicate delivery produces an identical key

- **WHEN** the same event is delivered twice
- **THEN** both parsed events MUST produce identical dedupe keys

#### Scenario: Distinct events produce distinct keys

- **WHEN** two different events are received
- **THEN** their dedupe keys MUST differ

#### Scenario: Responsibility for idempotency is documented

- **WHEN** a developer reads the webhook documentation
- **THEN** it MUST state that the application is responsible for storing keys and rejecting replays

### Requirement: Response semantics

Because Flodesk accepts any 2XX status as acknowledgement, a successfully verified and parsed event SHALL result in a 2XX response, and a rejected request MUST NOT return 2XX.

#### Scenario: Event accepted

- **WHEN** an event is verified, parsed, and dispatched successfully
- **THEN** a 2XX status MUST be returned

#### Scenario: Verification failed

- **WHEN** verification rejects a request
- **THEN** a non-2XX status MUST be returned and no event may be dispatched

#### Scenario: Application handler raises

- **WHEN** the application's event handler raises an exception
- **THEN** a non-2XX status MUST be returned, so Flodesk does not treat an unprocessed event as delivered

### Requirement: PII handling in inbound payloads

Because webhook payloads embed `email` and `optin_ip`, the gem SHALL NOT log or instrument inbound payload contents. Subscriber `id` MAY be used to identify an event in logs.

#### Scenario: Inbound event logged

- **WHEN** the gem logs the receipt of a webhook event
- **THEN** the output MUST NOT contain the subscriber's email address or opt-in IP

#### Scenario: Rejected request logged

- **WHEN** the gem logs a verification failure
- **THEN** the output MUST NOT contain the expected or supplied token, nor any payload PII
