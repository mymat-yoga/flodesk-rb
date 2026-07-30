# Rails Integration

## Purpose

Optional Rails conveniences: an install generator, a Railtie, request instrumentation, and test helpers. All load conditionally; the gem functions fully in a plain Ruby process and declares no runtime dependency on Rails or ActiveSupport.

## Requirements

### Requirement: Rails integration loads conditionally

The gem SHALL function fully without Rails and MUST NOT declare Rails as a runtime dependency. Rails-specific code MUST load only when Rails is present.

#### Scenario: Used in a plain Ruby script

- **WHEN** the gem is required in a process where Rails is not defined
- **THEN** all client and resource functionality MUST work and no Rails constant may be referenced

#### Scenario: Used in a Rails application

- **WHEN** the gem is required in a Rails application
- **THEN** the Railtie MUST load and register the gem's Rails integration

### Requirement: Install generator

The gem SHALL provide `rails g flodesk:install`, writing `config/initializers/flodesk.rb` that constructs a client from `Rails.application.credentials` and assigns it to a constant in the host application. The generator MUST NOT introduce gem-level global configuration, since the gem holds no global state.

#### Scenario: Running the generator

- **WHEN** a developer runs `rails g flodesk:install`
- **THEN** `config/initializers/flodesk.rb` MUST be created, constructing a `Flodesk::Client` from credentials and assigning it to a constant

#### Scenario: Generated initializer sets an app name

- **WHEN** the generator writes the initializer
- **THEN** it MUST include an `app_name` argument, because the API expects an identifying `User-Agent`

#### Scenario: Initializer already exists

- **WHEN** a developer runs the generator and `config/initializers/flodesk.rb` already exists
- **THEN** the generator MUST NOT silently overwrite it

#### Scenario: Credentials key is documented

- **WHEN** the generator completes
- **THEN** it MUST report which credentials key to populate and MUST NOT write an API key into the repository

### Requirement: Client is safe as an application constant

Because the generator assigns a client to a constant shared across request threads, the gem SHALL guarantee that a single client instance is safe for concurrent use.

#### Scenario: Concurrent requests through one constant

- **WHEN** many threads issue requests through the same client constant simultaneously
- **THEN** every request MUST complete correctly with no shared mutable state between them

### Requirement: Instrumentation via ActiveSupport::Notifications

When ActiveSupport is available, the gem SHALL emit a `flodesk.request` notification for every HTTP request, carrying the endpoint, HTTP method, status, duration, retry count, and observed rate-limit remaining. Payloads MUST NOT contain PII.

#### Scenario: Successful request emits an event

- **WHEN** a request completes successfully
- **THEN** a `flodesk.request` notification MUST be emitted with method, endpoint, status, and duration

#### Scenario: Failed request emits an event

- **WHEN** a request fails
- **THEN** a `flodesk.request` notification MUST still be emitted, recording the failure

#### Scenario: Retried request records attempts

- **WHEN** a request is retried before succeeding
- **THEN** the notification MUST report the number of attempts made

#### Scenario: Rate limit state included

- **WHEN** a response carries `X-Fd-RateLimit-Remaining`
- **THEN** that value MUST be included in the notification payload

#### Scenario: PII excluded from the payload

- **WHEN** a request concerns a subscriber identified by email, or carries custom fields or an opt-in IP
- **THEN** the notification payload MUST NOT contain the email address, custom field values, or opt-in IP

#### Scenario: Email in a URL path is redacted

- **WHEN** a request targets `GET /subscribers/{email}` using an email address
- **THEN** the endpoint recorded in the notification MUST have the email redacted rather than embedded

#### Scenario: ActiveSupport absent

- **WHEN** the gem runs without ActiveSupport available
- **THEN** requests MUST still succeed and no instrumentation may be attempted

### Requirement: Test helpers

The gem SHALL ship test helpers providing WebMock stubs and fixture payloads derived from the vendored OpenAPI specification, so host applications can test Flodesk integrations without hand-writing stub JSON. Helpers MUST be opt-in via an explicit require and MUST NOT affect production code paths.

#### Scenario: Stubbing a successful upsert

- **WHEN** a host application uses the provided helper to stub a subscriber upsert
- **THEN** the call MUST return a `Subscriber` built from a spec-derived payload, with no real HTTP request made

#### Scenario: Stubbing an error response

- **WHEN** a host application uses the helper to stub a `404`
- **THEN** the call MUST raise `Flodesk::NotFoundError`

#### Scenario: Stubbing a partial batch failure

- **WHEN** a host application uses the helper to stub a batch response containing failures
- **THEN** the call MUST raise `Flodesk::PartialFailureError` carrying the stubbed successes and failures

#### Scenario: Helpers not required

- **WHEN** an application requires only the gem's main entry point
- **THEN** no test helper or WebMock code may be loaded

### Requirement: Documented log filtering for sensitive paths

Because webhook payloads carry `email` and `optin_ip`, and the token-in-path verification strategy places a secret in a URL that Rails logs, installation documentation SHALL cover filtering the webhook route from Rails logs.

#### Scenario: Reading installation documentation

- **WHEN** a developer follows the webhook installation instructions
- **THEN** the documentation MUST explain how to keep the callback path and payload contents out of Rails logs
