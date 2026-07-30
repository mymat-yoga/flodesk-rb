## ADDED Requirements

### Requirement: Uniform pagination interface

All list operations SHALL accept the same `page:` and `per_page:` keyword arguments regardless of the parameter names the underlying endpoint expects. The gem MUST translate them per endpoint: `per_page` for subscribers, segments, custom fields, webhooks, and campaigns; `perPage` for `GET /workflows`. Callers MUST never need to know which spelling an endpoint uses.

#### Scenario: Listing subscribers with pagination

- **WHEN** a caller invokes the subscribers list with `page: 2, per_page: 50`
- **THEN** the request query string MUST contain `page=2` and `per_page=50`

#### Scenario: Listing workflows with pagination

- **WHEN** a caller invokes the workflows list with `page: 2, per_page: 50`
- **THEN** the request query string MUST contain `page=2` and `perPage=50`, translated from the same caller-facing arguments

#### Scenario: Pagination arguments omitted

- **WHEN** a caller invokes a list operation with no pagination arguments
- **THEN** no pagination parameters may be sent, and the API's defaults of page 1 and 20 per page apply

### Requirement: per_page bounds

Because the API caps `per_page` at 100, the gem SHALL reject values above 100 or below 1 with an `ArgumentError` before issuing a request, rather than sending a value the API will refuse.

#### Scenario: per_page above the cap

- **WHEN** a caller passes `per_page: 500`
- **THEN** an `ArgumentError` MUST be raised and no HTTP request may be made

#### Scenario: per_page at the cap

- **WHEN** a caller passes `per_page: 100`
- **THEN** the request MUST be issued normally

#### Scenario: per_page below one

- **WHEN** a caller passes `per_page: 0`
- **THEN** an `ArgumentError` MUST be raised and no HTTP request may be made

### Requirement: Page object

List operations SHALL return a `Flodesk::Page` exposing the parsed `items` alongside `page`, `per_page`, `total_pages`, and `total_items` read from the response `meta` object. `Page` MUST be `Enumerable` over its items and MUST expose `#to_h` returning the raw payload.

#### Scenario: Reading pagination metadata

- **WHEN** a list response contains `meta` with `page`, `total_pages`, `per_page`, and `total_items`
- **THEN** the returned `Page` MUST expose all four values as integers

#### Scenario: Iterating a page

- **WHEN** a caller iterates the returned `Page`
- **THEN** it MUST yield the parsed value objects for that page only, without issuing further requests

#### Scenario: Empty result set

- **WHEN** a list response contains an empty `data` array
- **THEN** the `Page` MUST be empty, MUST NOT raise, and MUST still expose its metadata

#### Scenario: meta object absent

- **WHEN** a list response omits `meta`
- **THEN** the `Page` MUST still return its items with metadata readers returning `nil`

#### Scenario: Determining whether more pages exist

- **WHEN** a caller holds a `Page` whose `page` is less than `total_pages`
- **THEN** the `Page` MUST report that a further page is available

### Requirement: Opt-in auto-paging

The gem SHALL provide `auto_paging_each` on list operations, returning a lazy `Enumerator` that fetches subsequent pages on demand. Auto-paging MUST NOT be the default behavior of `list`, because traversing a large collection can consume the entire 100 requests-per-minute budget in a single loop and that cost must remain visible at the call site.

#### Scenario: Traversing all pages

- **WHEN** a caller uses `auto_paging_each` across a collection spanning three pages
- **THEN** every item from all three pages MUST be yielded in order

#### Scenario: Lazy evaluation halts requests early

- **WHEN** a caller takes only the first item from `auto_paging_each`
- **THEN** only the first page may be requested

#### Scenario: Auto-paging respects per_page

- **WHEN** a caller invokes `auto_paging_each` with `per_page: 100`
- **THEN** every page request MUST use the endpoint's correct per-page parameter name with value 100

#### Scenario: Error mid-traversal

- **WHEN** fetching the second page raises a `Flodesk::Error`
- **THEN** the error MUST propagate to the caller rather than silently ending iteration

#### Scenario: list does not auto-page

- **WHEN** a caller invokes `list` on a collection spanning several pages
- **THEN** exactly one HTTP request may be made

### Requirement: Endpoint-specific filters

List operations SHALL accept their documented filters using idiomatic snake_case keyword arguments, translating to whatever casing the endpoint requires. `GET /subscribers` supports `status` and `segment_id`; `GET /workflows` supports `statuses`; `GET /campaigns` supports `search`, `order_by`, `sort`, `status`, and `shared_as_template`, which MUST be sent as the PascalCase parameters `Search`, `OrderBy`, `Sort`, `Status`, and `SharedAsTemplate`.

#### Scenario: Filtering subscribers by status and segment

- **WHEN** a caller lists subscribers with `status: :active, segment_id: "seg_1"`
- **THEN** the query string MUST contain `status=active` and `segment_id=seg_1`

#### Scenario: Filtering campaigns

- **WHEN** a caller lists campaigns with `search: "spring", status: :draft, shared_as_template: true`
- **THEN** the query string MUST contain `Search=spring`, `Status=draft`, and `SharedAsTemplate=true`

#### Scenario: Filtering workflows by statuses

- **WHEN** a caller lists workflows with an array of statuses
- **THEN** the `statuses` parameter MUST be serialized as the API expects for an array parameter

#### Scenario: Invalid enum filter value

- **WHEN** a caller passes a status value outside the documented enum
- **THEN** an `ArgumentError` MUST be raised before any HTTP request is made
