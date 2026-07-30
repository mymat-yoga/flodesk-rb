## ADDED Requirements

### Requirement: List custom fields

The client SHALL expose a paginated list operation mapping to `GET /custom-fields`, accepting `page` and `per_page`, and returning a `Page` of `CustomField` objects.

#### Scenario: Listing custom fields

- **WHEN** a caller lists custom fields
- **THEN** `GET /custom-fields` MUST be issued and a `Page` of `CustomField` objects returned

#### Scenario: Paginating custom fields

- **WHEN** a caller lists custom fields with `page: 2, per_page: 50`
- **THEN** the query string MUST contain `page=2` and `per_page=50`

#### Scenario: No custom fields exist

- **WHEN** the account has no custom fields
- **THEN** an empty `Page` MUST be returned without raising

### Requirement: List all custom fields

The client SHALL expose a separate operation mapping to `GET /custom-fields/all`, returning every custom field without pagination. The distinction from the paginated list MUST be documented, since the two endpoints are easily confused.

#### Scenario: Listing all custom fields

- **WHEN** a caller requests all custom fields
- **THEN** `GET /custom-fields/all` MUST be issued and every `CustomField` returned

#### Scenario: All-fields operation ignores pagination

- **WHEN** a caller requests all custom fields
- **THEN** no pagination parameters may be sent, because the endpoint is not paginated

### Requirement: Create a custom field

The client SHALL expose a create operation mapping to `POST /custom-fields`, returning the created `CustomField`. Because the endpoint creates a new record and the API offers no idempotency key, the operation MUST be declared **non-idempotent** and MUST NOT be retried on server errors or timeouts.

#### Scenario: Creating a custom field

- **WHEN** a caller creates a custom field
- **THEN** `POST /custom-fields` MUST be issued and the created `CustomField` returned

#### Scenario: Server error during creation

- **WHEN** `POST /custom-fields` returns `503`
- **THEN** the request MUST NOT be retried, to avoid creating a duplicate field, and a `Flodesk::ServerError` MUST be raised

#### Scenario: Timeout during creation

- **WHEN** `POST /custom-fields` times out
- **THEN** the request MUST NOT be retried and a `Flodesk::TimeoutError` MUST be raised

#### Scenario: Invalid creation payload

- **WHEN** the API responds `400`
- **THEN** a `Flodesk::BadRequestError` MUST be raised without retrying

### Requirement: Custom field values are string-typed

The gem SHALL document that Flodesk stores all custom field values as strings, so callers understand why numeric and boolean values require handling on write paths.

#### Scenario: Reading a custom field value

- **WHEN** a subscriber's custom fields are read
- **THEN** every value MUST be exposed as a string, matching the API's schema
