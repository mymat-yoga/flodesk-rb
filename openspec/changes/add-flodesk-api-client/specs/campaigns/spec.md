## ADDED Requirements

### Requirement: List campaigns

The client SHALL expose a campaigns list operation mapping to `GET /campaigns`, returning a `Page` of `Campaign` objects. It MUST accept idiomatic snake_case arguments `page`, `per_page`, `search`, `order_by`, `sort`, `status`, and `shared_as_template`, translating them to the PascalCase parameters the endpoint requires: `Search`, `OrderBy`, `Sort`, `Status`, and `SharedAsTemplate`. Callers MUST never need to write PascalCase.

#### Scenario: Listing campaigns

- **WHEN** a caller lists campaigns
- **THEN** `GET /campaigns` MUST be issued and a `Page` of `Campaign` objects returned

#### Scenario: Searching campaigns

- **WHEN** a caller lists campaigns with `search: "spring sale"`
- **THEN** the query string MUST contain `Search=spring+sale` and MUST NOT contain `search`

#### Scenario: Filtering by status

- **WHEN** a caller lists campaigns with `status: :draft`
- **THEN** the query string MUST contain `Status=draft`

#### Scenario: Sorting campaigns

- **WHEN** a caller lists campaigns with `order_by` and `sort`
- **THEN** the query string MUST contain `OrderBy` and `Sort` with those values

#### Scenario: Filtering by shared-as-template

- **WHEN** a caller lists campaigns with `shared_as_template: true`
- **THEN** the query string MUST contain `SharedAsTemplate=true`

#### Scenario: Invalid status value

- **WHEN** a caller passes a status outside `draft`, `pending`, `scheduled`, `composing`, `sending`, `done`, and `failed`
- **THEN** an `ArgumentError` MUST be raised before any HTTP request is made

#### Scenario: Pagination uses snake_case here

- **WHEN** a caller lists campaigns with `page: 2, per_page: 50`
- **THEN** the query string MUST contain `page=2` and `per_page=50`, since this endpoint uses snake_case for pagination despite PascalCase filters

### Requirement: Publish a Canva email campaign

The client SHALL expose an operation mapping to `POST /campaigns/canva`, returning the created campaign on `201`. This operation publishes an email campaign, so it MUST be declared **non-idempotent** and MUST NOT be retried under any circumstances, including timeouts and `5xx` responses. A retry could send the campaign to the entire subscriber list a second time, which is unrecoverable and customer-visible. The implementation MUST carry an explicit comment recording this.

#### Scenario: Publishing a Canva campaign

- **WHEN** a caller publishes a Canva email campaign
- **THEN** `POST /campaigns/canva` MUST be issued and the created campaign returned from the `201` response

#### Scenario: Server error during publish

- **WHEN** `POST /campaigns/canva` returns `503`
- **THEN** the request MUST NOT be retried and a `Flodesk::ServerError` MUST be raised

#### Scenario: Timeout during publish

- **WHEN** `POST /campaigns/canva` times out
- **THEN** the request MUST NOT be retried and a `Flodesk::TimeoutError` MUST be raised, because the campaign may already have been published

#### Scenario: Rate limited during publish

- **WHEN** `POST /campaigns/canva` returns `429`
- **THEN** the request MUST NOT be retried automatically, because a `429` cannot prove the campaign was not accepted, and a `Flodesk::RateLimitError` MUST be raised

#### Scenario: Invalid publish payload

- **WHEN** the API responds `400`
- **THEN** a `Flodesk::BadRequestError` MUST be raised

### Requirement: Retrieve Canva design state

The client SHALL expose an operation mapping to `GET /campaigns/canva/design-state`, returning the design state.

#### Scenario: Retrieving design state

- **WHEN** a caller requests the Canva design state
- **THEN** `GET /campaigns/canva/design-state` MUST be issued and the state returned

#### Scenario: Design state not found

- **WHEN** the API responds `404`
- **THEN** a `Flodesk::NotFoundError` MUST be raised

### Requirement: Maturity disclosure

Because the Canva campaign endpoints cannot be safely exercised against a live account during development, documentation SHALL state that they are covered only by specification-derived stubs and are less battle-tested than the subscriber and segment operations.

#### Scenario: Documented maturity caveat

- **WHEN** a developer reads the campaigns documentation
- **THEN** it MUST disclose the reduced real-world coverage of the Canva endpoints
