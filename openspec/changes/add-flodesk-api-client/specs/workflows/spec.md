## ADDED Requirements

### Requirement: List workflows

The client SHALL expose a workflows list operation mapping to `GET /workflows`, accepting `page`, `per_page`, and `statuses`, and returning a `Page` of `Workflow` objects. This endpoint expects `perPage` rather than `per_page`, and the gem MUST translate the uniform caller-facing argument to that spelling.

#### Scenario: Listing workflows

- **WHEN** a caller lists workflows
- **THEN** `GET /workflows` MUST be issued and a `Page` of `Workflow` objects returned

#### Scenario: Paginating workflows uses camelCase

- **WHEN** a caller lists workflows with `page: 2, per_page: 50`
- **THEN** the query string MUST contain `page=2` and `perPage=50`, and MUST NOT contain `per_page`

#### Scenario: Filtering by statuses

- **WHEN** a caller lists workflows with a `statuses` array
- **THEN** the `statuses` parameter MUST be serialized as the API expects for an array parameter

#### Scenario: No workflows exist

- **WHEN** the account has no workflows
- **THEN** an empty `Page` MUST be returned without raising

#### Scenario: Endpoint responds 404

- **WHEN** the API responds `404`, which this list endpoint documents
- **THEN** a `Flodesk::NotFoundError` MUST be raised

### Requirement: Add a subscriber to a workflow

The client SHALL expose an operation mapping to `POST /workflows/{workflow_id}/subscribers`. The endpoint returns `204 No Content`, so the gem MUST NOT attempt to parse a response body. The operation MUST be declared idempotent because adding an already-enrolled subscriber has no additional effect.

#### Scenario: Adding a subscriber

- **WHEN** a caller adds a subscriber to a workflow
- **THEN** `POST /workflows/{workflow_id}/subscribers` MUST be issued and the method MUST return successfully without parsing a body

#### Scenario: Workflow does not exist

- **WHEN** the API responds `404`
- **THEN** a `Flodesk::NotFoundError` MUST be raised

#### Scenario: Invalid request

- **WHEN** the API responds `400`
- **THEN** a `Flodesk::BadRequestError` MUST be raised without retrying

#### Scenario: Server error is retried

- **WHEN** the request returns `503` and retries remain
- **THEN** the request MUST be retried, because the operation is idempotent

### Requirement: Remove a subscriber from a workflow

The client SHALL expose an operation mapping to `DELETE /workflows/{workflow_id}/subscribers/{id_or_email}`, accepting either an id or an email. The endpoint returns `204 No Content`, so no body may be parsed. The operation MUST be declared idempotent.

#### Scenario: Removing a subscriber by id

- **WHEN** a caller removes a subscriber from a workflow by id
- **THEN** `DELETE /workflows/{workflow_id}/subscribers/{id}` MUST be issued and the method MUST return successfully without parsing a body

#### Scenario: Removing a subscriber by email

- **WHEN** a caller removes a subscriber by email address
- **THEN** the email MUST be URL-encoded in the path

#### Scenario: Subscriber not enrolled

- **WHEN** the API responds `404`
- **THEN** a `Flodesk::NotFoundError` MUST be raised
