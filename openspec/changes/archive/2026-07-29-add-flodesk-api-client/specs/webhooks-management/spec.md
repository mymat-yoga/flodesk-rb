## ADDED Requirements

### Requirement: List webhooks

The client SHALL expose a webhooks list operation mapping to `GET /webhooks`, accepting `page` and `per_page`, and returning a `Page` of `Webhook` objects exposing `id`, `post_url`, `events`, and `created_at`.

#### Scenario: Listing webhooks

- **WHEN** a caller lists webhooks
- **THEN** `GET /webhooks` MUST be issued and a `Page` of `Webhook` objects returned

#### Scenario: No webhooks registered

- **WHEN** the account has no webhooks
- **THEN** an empty `Page` MUST be returned without raising

### Requirement: Retrieve a webhook

The client SHALL expose a retrieve operation mapping to `GET /webhooks/{id}`, returning a `Webhook`.

#### Scenario: Retrieving an existing webhook

- **WHEN** a caller retrieves a webhook by id
- **THEN** `GET /webhooks/{id}` MUST be issued and a `Webhook` returned

#### Scenario: Webhook does not exist

- **WHEN** the API responds `404`
- **THEN** a `Flodesk::NotFoundError` MUST be raised

### Requirement: Create a webhook

The client SHALL expose a create operation mapping to `POST /webhooks`, accepting `post_url` and `events`, and returning the created `Webhook`. Because the endpoint creates a new record and the API offers no idempotency key, the operation MUST be declared **non-idempotent** and MUST NOT be retried on server errors or timeouts.

#### Scenario: Creating a webhook

- **WHEN** a caller creates a webhook with a post URL and events
- **THEN** `POST /webhooks` MUST be issued and the created `Webhook` returned with its generated id

#### Scenario: Server error during creation

- **WHEN** `POST /webhooks` returns `503`
- **THEN** the request MUST NOT be retried, to avoid registering a duplicate webhook, and a `Flodesk::ServerError` MUST be raised

#### Scenario: Unknown event name

- **WHEN** a caller supplies an event name outside `subscriber.created`, `subscriber.added_to_segment`, and `subscriber.unsubscribed`
- **THEN** an `ArgumentError` MUST be raised before any HTTP request is made

#### Scenario: Invalid creation payload

- **WHEN** the API responds `400`
- **THEN** a `Flodesk::BadRequestError` MUST be raised without retrying

### Requirement: Update a webhook

The client SHALL expose an update operation mapping to `PUT /webhooks/{id}`, returning the updated `Webhook`. Because `PUT` replaces the record's state, the operation MUST be declared idempotent.

#### Scenario: Updating a webhook

- **WHEN** a caller updates a webhook's post URL or events
- **THEN** `PUT /webhooks/{id}` MUST be issued and the updated `Webhook` returned

#### Scenario: Webhook does not exist

- **WHEN** the API responds `404`
- **THEN** a `Flodesk::NotFoundError` MUST be raised

#### Scenario: Server error is retried

- **WHEN** the request returns `503` and retries remain
- **THEN** the request MUST be retried, because `PUT` is idempotent

### Requirement: Delete a webhook

The client SHALL expose a delete operation mapping to `DELETE /webhooks/{id}`. The endpoint returns `204 No Content`, so the gem MUST NOT attempt to parse a response body. The operation MUST be declared idempotent.

#### Scenario: Deleting a webhook

- **WHEN** a caller deletes a webhook by id
- **THEN** `DELETE /webhooks/{id}` MUST be issued and the method MUST return successfully without parsing a body

#### Scenario: Webhook already deleted

- **WHEN** the API responds `404`
- **THEN** a `Flodesk::NotFoundError` MUST be raised

### Requirement: Registration guidance for unverifiable callbacks

Because Flodesk provides no webhook signing mechanism, documentation for the create operation SHALL direct callers to register a `post_url` compatible with one of the supported verification strategies, so registration and verification are designed together rather than separately.

#### Scenario: Documented registration guidance

- **WHEN** a developer reads the create-webhook documentation
- **THEN** it MUST state that no signature mechanism exists and reference the supported verification strategies
