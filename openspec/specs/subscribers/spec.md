# Subscribers

## Purpose

The subscriber lifecycle: listing, retrieval, upsert, batch upsert, segment membership, and unsubscribing. Carries the API's two sharpest edges — upsert cannot report whether a record was created or updated, and batch operations report per-record failures inside a success response.

## Requirements

### Requirement: List subscribers

The client SHALL expose a subscribers list operation mapping to `GET /subscribers`, accepting `page`, `per_page`, `status`, and `segment_id`, and returning a `Page` of `Subscriber` objects.

#### Scenario: Listing all subscribers

- **WHEN** a caller lists subscribers with no arguments
- **THEN** `GET /subscribers` MUST be issued and a `Page` of `Subscriber` objects returned

#### Scenario: Filtering by status

- **WHEN** a caller lists subscribers with `status: :unsubscribed`
- **THEN** the query string MUST contain `status=unsubscribed`

#### Scenario: Filtering by segment

- **WHEN** a caller lists subscribers with `segment_id: "seg_1"`
- **THEN** the query string MUST contain `segment_id=seg_1`

### Requirement: Retrieve a subscriber

The client SHALL expose a retrieve operation mapping to `GET /subscribers/{id_or_email}`, accepting either an id or an email address, and returning a `Subscriber`.

#### Scenario: Retrieve by id

- **WHEN** a caller retrieves a subscriber by id
- **THEN** `GET /subscribers/{id}` MUST be issued and a `Subscriber` returned

#### Scenario: Retrieve by email

- **WHEN** a caller retrieves a subscriber by email address
- **THEN** the email MUST be URL-encoded in the path and a `Subscriber` returned

#### Scenario: Email containing a plus sign

- **WHEN** a caller retrieves a subscriber whose email contains `+`
- **THEN** the path segment MUST be encoded so the API receives the literal address

#### Scenario: Subscriber does not exist

- **WHEN** the API responds `404`
- **THEN** a `Flodesk::NotFoundError` MUST be raised

### Requirement: Upsert a subscriber

The client SHALL expose an upsert operation mapping to `POST /subscribers`, accepting `id`, `email`, `first_name`, `last_name`, `custom_fields`, `segment_ids`, `double_optin`, `optin_ip`, and `optin_timestamp`, and returning the resulting `Subscriber`. The operation MUST be declared idempotent for retry purposes. Because the API returns `200` for both creation and update and never reports which occurred, the gem MUST NOT claim to distinguish them.

#### Scenario: Creating a new subscriber

- **WHEN** a caller upserts with an email not yet on the list
- **THEN** `POST /subscribers` MUST be issued and the resulting `Subscriber` returned

#### Scenario: Updating an existing subscriber

- **WHEN** a caller upserts with an email already on the list
- **THEN** the same `POST /subscribers` request MUST be issued and the updated `Subscriber` returned

#### Scenario: Neither id nor email supplied

- **WHEN** a caller upserts without an `id` or an `email`
- **THEN** an `ArgumentError` MUST be raised before any HTTP request, because the API requires one of them

#### Scenario: Assigning segments during upsert

- **WHEN** a caller upserts with `segment_ids`
- **THEN** those ids MUST be sent in the request body

#### Scenario: More than fifty segment ids

- **WHEN** a caller upserts with more than 50 segment ids
- **THEN** an `ArgumentError` MUST be raised, because the API caps segments per subscriber at 50

#### Scenario: Requesting double opt-in

- **WHEN** a caller upserts a new subscriber with `double_optin: true`
- **THEN** `double_optin` MUST be sent in the request body

#### Scenario: Upsert retried after a server error

- **WHEN** `POST /subscribers` returns `503` and retries remain
- **THEN** the request MUST be retried, because upsert is idempotent

### Requirement: Batch upsert subscribers

The client SHALL expose a batch upsert mapping to `POST /subscribers/batch`, accepting up to 50 subscriber payloads and returning a `BatchResult`. The operation MUST be declared idempotent. Because the API returns `200` carrying both `successes` and `failures`, the gem MUST raise `Flodesk::PartialFailureError` by default when any record fails, and MUST return the `BatchResult` without raising when `raise_on_failure: false` is passed.

#### Scenario: All records succeed

- **WHEN** every submitted record is accepted
- **THEN** a `BatchResult` MUST be returned with `#success?` true and no exception raised

#### Scenario: Some records fail with default behavior

- **WHEN** the response contains at least one entry in `failures`
- **THEN** a `Flodesk::PartialFailureError` MUST be raised carrying the complete `BatchResult`

#### Scenario: Some records fail with raising disabled

- **WHEN** the response contains failures and the caller passed `raise_on_failure: false`
- **THEN** the `BatchResult` MUST be returned with `#success?` false and no exception raised

#### Scenario: Inspecting failures

- **WHEN** a caller examines a `BatchResult` containing failures
- **THEN** each failure MUST expose `index`, `email`, `id`, `code`, and `message`, so the failing subset can be retried

#### Scenario: Successes preserved when raising

- **WHEN** a `Flodesk::PartialFailureError` is raised for a mixed response
- **THEN** the successful `Subscriber` records MUST remain accessible through the error's result

#### Scenario: More than fifty records submitted

- **WHEN** a caller submits more than 50 subscriber payloads in one call
- **THEN** an `ArgumentError` MUST be raised before any HTTP request, because the API caps a batch at 50

#### Scenario: Empty batch

- **WHEN** a caller submits an empty array
- **THEN** an `ArgumentError` MUST be raised and no HTTP request may be made

### Requirement: Add a subscriber to segments

The client SHALL expose an operation mapping to `POST /subscribers/{id_or_email}/segments`, accepting segment ids, and MUST declare it idempotent because adding an already-present segment has no additional effect.

#### Scenario: Adding segments

- **WHEN** a caller adds segment ids to a subscriber
- **THEN** `POST /subscribers/{id_or_email}/segments` MUST be issued with those ids in the body

#### Scenario: Adding a segment the subscriber already has

- **WHEN** a caller adds a segment already assigned to the subscriber
- **THEN** the request MUST succeed without error

#### Scenario: Subscriber does not exist

- **WHEN** the API responds `404`
- **THEN** a `Flodesk::NotFoundError` MUST be raised

### Requirement: Remove a subscriber from segments

The client SHALL expose an operation mapping to `DELETE /subscribers/{id_or_email}/segments`, accepting segment ids, and MUST declare it idempotent.

#### Scenario: Removing segments

- **WHEN** a caller removes segment ids from a subscriber
- **THEN** `DELETE /subscribers/{id_or_email}/segments` MUST be issued with those ids

#### Scenario: Removing a segment the subscriber does not have

- **WHEN** a caller removes a segment not assigned to the subscriber
- **THEN** the request MUST succeed without error

### Requirement: Unsubscribe a subscriber

The client SHALL expose an unsubscribe operation mapping to `POST /subscribers/{id_or_email}/unsubscribe`, declared idempotent because the result is a terminal state.

#### Scenario: Unsubscribing an active subscriber

- **WHEN** a caller unsubscribes an active subscriber
- **THEN** `POST /subscribers/{id_or_email}/unsubscribe` MUST be issued

#### Scenario: Unsubscribing an already-unsubscribed subscriber

- **WHEN** a caller unsubscribes a subscriber already unsubscribed
- **THEN** the request MUST succeed without error

### Requirement: Custom field values are strings

Because the API types `custom_fields` values as `string` only, the gem SHALL apply one consistent, documented rule for non-string values on every write path that accepts custom fields.

#### Scenario: String custom field values

- **WHEN** a caller supplies custom fields with string values
- **THEN** they MUST be sent unchanged

#### Scenario: Non-string custom field value

- **WHEN** a caller supplies a custom field value that is not a string, such as `true` or `42`
- **THEN** the gem MUST apply its documented rule consistently and MUST NOT silently send a payload the API will reject
