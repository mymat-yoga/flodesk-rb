# Segments

## Purpose

Segment listing, retrieval, creation, and the available colour palette. Segment creation is not idempotent and must never be retried, since a repeat would leave a duplicate segment behind.

## Requirements

### Requirement: List segments

The client SHALL expose a segments list operation mapping to `GET /segments`, accepting `page` and `per_page`, and returning a `Page` of `Segment` objects.

#### Scenario: Listing segments

- **WHEN** a caller lists segments
- **THEN** `GET /segments` MUST be issued and a `Page` of `Segment` objects returned

#### Scenario: Paginating segments

- **WHEN** a caller lists segments with `page: 2, per_page: 50`
- **THEN** the query string MUST contain `page=2` and `per_page=50`

#### Scenario: No segments exist

- **WHEN** the account has no segments
- **THEN** an empty `Page` MUST be returned without raising

### Requirement: Retrieve a segment

The client SHALL expose a retrieve operation mapping to `GET /segments/{id}`, returning a `Segment`.

#### Scenario: Retrieving an existing segment

- **WHEN** a caller retrieves a segment by id
- **THEN** `GET /segments/{id}` MUST be issued and a `Segment` returned

#### Scenario: Segment does not exist

- **WHEN** the API responds `404`
- **THEN** a `Flodesk::NotFoundError` MUST be raised

### Requirement: Create a segment

The client SHALL expose a create operation mapping to `POST /segments`, returning the created `Segment`. Because the endpoint creates a new record and the API offers no idempotency key, the operation MUST be declared **non-idempotent** and MUST NOT be retried on server errors or timeouts.

#### Scenario: Creating a segment

- **WHEN** a caller creates a segment with a name
- **THEN** `POST /segments` MUST be issued and the created `Segment` returned with its generated id

#### Scenario: Server error during creation

- **WHEN** `POST /segments` returns `503`
- **THEN** the request MUST NOT be retried, to avoid creating a duplicate segment, and a `Flodesk::ServerError` MUST be raised

#### Scenario: Timeout during creation

- **WHEN** `POST /segments` times out
- **THEN** the request MUST NOT be retried and a `Flodesk::TimeoutError` MUST be raised, since the segment may in fact have been created

#### Scenario: Invalid creation payload

- **WHEN** the API responds `400`
- **THEN** a `Flodesk::BadRequestError` MUST be raised without retrying

### Requirement: List segment colors

The client SHALL expose an operation mapping to `GET /segments/colors`, returning the available segment colors.

#### Scenario: Listing colors

- **WHEN** a caller lists segment colors
- **THEN** `GET /segments/colors` MUST be issued and the colors returned

#### Scenario: Unauthorized

- **WHEN** the API responds `401`, the only error documented for this endpoint
- **THEN** a `Flodesk::AuthenticationError` MUST be raised
