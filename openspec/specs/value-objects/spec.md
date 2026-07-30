# Value Objects

## Purpose

Immutable typed representations of API responses. Every object exposes the raw payload alongside its declared attributes, so a field Flodesk adds is reachable immediately without waiting for a gem release, and unrecognized enum values or timestamps pass through rather than raising.

## Requirements

### Requirement: Immutable typed response objects

API responses SHALL be returned as immutable value objects built with `Data.define`, one per documented response schema: `Subscriber`, `Segment`, `CustomField`, `Workflow`, `Webhook`, `Campaign`, `Page`, `BatchResult`, and `BatchItemError`. Attributes MUST be readable as methods, so a misspelled attribute raises `NoMethodError` instead of returning `nil`.

#### Scenario: Reading a subscriber attribute

- **WHEN** a subscriber is retrieved
- **THEN** `#email`, `#first_name`, `#last_name`, `#id`, `#created_at`, and `#status` MUST all be readable as methods

#### Scenario: Misspelled attribute

- **WHEN** a caller invokes a method that is not a defined attribute
- **THEN** a `NoMethodError` MUST be raised

#### Scenario: Objects are frozen

- **WHEN** a caller attempts to mutate a returned value object
- **THEN** the attempt MUST fail, because value objects are immutable

#### Scenario: Value equality

- **WHEN** two value objects are built from identical payloads
- **THEN** they MUST compare as equal

### Requirement: Raw payload escape hatch

Every value object SHALL expose `#to_h` returning the raw parsed payload as received from the API. Fields present in the response but not declared as attributes MUST be preserved in that payload and MUST NOT cause an error. This guarantees that a field Flodesk adds is reachable immediately, without waiting for a gem release.

#### Scenario: Undeclared field in the response

- **WHEN** the API returns a subscriber containing a field the gem does not declare
- **THEN** parsing MUST succeed and the field MUST be readable via `#to_h`

#### Scenario: Declared field missing from the response

- **WHEN** the API returns a subscriber omitting an optional declared field
- **THEN** the corresponding reader MUST return `nil` rather than raising

#### Scenario: Round-tripping a payload

- **WHEN** a caller reads `#to_h` from a parsed object
- **THEN** the result MUST equal the original parsed response body for that object

### Requirement: Enum coercion with pass-through for unknown values

Attributes documented as closed enums SHALL be exposed as symbols. `Subscriber#status` covers `active`, `unsubscribed`, `unconfirmed`, `bounced`, `complained`, and `cleaned`. `Subscriber#source` covers `manual`, `csv`, `form_optin`, `integration`, and `checkout`. A value outside the documented set MUST be passed through rather than raising, so a newly introduced Flodesk value cannot break existing callers.

#### Scenario: Known status value

- **WHEN** a subscriber response has `"status": "active"`
- **THEN** `#status` MUST return `:active`

#### Scenario: Known source value

- **WHEN** a subscriber response has `"source": "form_optin"`
- **THEN** `#source` MUST return `:form_optin`

#### Scenario: Unknown enum value

- **WHEN** a subscriber response has a `status` value outside the documented enum
- **THEN** parsing MUST succeed, the value MUST remain retrievable, and no error may be raised

#### Scenario: Enum field absent

- **WHEN** a subscriber response omits `status`
- **THEN** `#status` MUST return `nil`

### Requirement: Timestamp coercion

Attributes documented with `format: date-time` — including `created_at`, `optin_timestamp`, and webhook `event_time` — SHALL be exposed as `Time` objects parsed from ISO 8601. An unparseable value MUST be passed through unchanged rather than raising.

#### Scenario: Valid ISO 8601 timestamp

- **WHEN** a response contains `"created_at": "2023-01-02T15:04:05.999Z"`
- **THEN** `#created_at` MUST return a `Time`

#### Scenario: Timestamp absent

- **WHEN** a response omits a timestamp field
- **THEN** the corresponding reader MUST return `nil`

#### Scenario: Unparseable timestamp

- **WHEN** a response contains a timestamp that is not valid ISO 8601
- **THEN** parsing MUST NOT raise and the raw value MUST remain retrievable

### Requirement: Nested object construction

Nested structures SHALL be parsed into their own value objects. A subscriber's `segments` MUST be an array of `Segment` objects, and a subscriber's `custom_fields` MUST be a hash of string keys to string values.

#### Scenario: Subscriber with segments

- **WHEN** a subscriber response includes a `segments` array
- **THEN** `#segments` MUST return an array of `Segment` objects, each with its attributes readable

#### Scenario: Subscriber with no segments

- **WHEN** a subscriber response omits `segments` or provides an empty array
- **THEN** `#segments` MUST return an empty array rather than `nil`

#### Scenario: Subscriber with custom fields

- **WHEN** a subscriber response includes `custom_fields`
- **THEN** `#custom_fields` MUST return a hash preserving the API's keys and string values

### Requirement: RBS signatures

The gem SHALL ship RBS signatures under `sig/` covering the public surface, including every value object attribute, resource method, and error class, replacing the generated `sig/flodesk/rb.rbs` stub.

#### Scenario: Type checking a value object

- **WHEN** RBS signatures are checked against the implementation
- **THEN** every value object attribute MUST have a declared type and validation MUST pass
