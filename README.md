# flodesk-rb

A dependency-free Ruby client for the [Flodesk API](https://developers.flodesk.com), built for Rails apps.

Covers all 25 documented operations across subscribers, segments, custom fields, workflows, webhooks and campaigns — and absorbs the API's rough edges so you don't have to think about them:

- **Pagination isn't uniform.** Most endpoints take `per_page`; `GET /workflows` takes `perPage`; `GET /campaigns` takes PascalCase filters. You always pass `page:` and `per_page:`.
- **Batch upsert reports failure inside a `200`.** A client that treats 2xx as success silently drops subscribers. Here, partial failure raises by default.
- **Retry safety is per-endpoint, not per-verb.** Most `POST`s are idempotent upserts, but four create records — and one *publishes an email campaign*. A generic "retry POST on 5xx" wrapper can send a campaign to your whole list twice.

## Installation

```ruby
gem "flodesk-rb"
```

Requires Ruby 3.2+. No runtime dependencies.

## Quick start

```ruby
client = Flodesk::Client.new(
  api_key:  ENV.fetch("FLODESK_API_KEY"),
  app_name: "MyApp (myapp.com)"   # the API asks integrations to identify themselves
)

client.subscribers.upsert(email: "ada@example.com", first_name: "Ada")
```

Create and manage API keys at [app.flodesk.com/account/integration/api](https://app.flodesk.com/account/integration/api).

### Rails

```bash
bin/rails g flodesk:install
bin/rails credentials:edit   # add: flodesk_api_key: fd_your_key_here
```

That writes `config/initializers/flodesk.rb` assigning a client to a `FLODESK` constant. The gem holds **no global configuration** — ownership stays visible in your app, and a second Flodesk account is just another `Flodesk::Client.new`. A client is frozen and safe to share across request threads.

## Configuration

```ruby
Flodesk::Client.new(
  api_key:       "fd_...",   # required
  app_name:      "MyApp",    # added to the User-Agent
  open_timeout:  5,
  read_timeout:  15,
  max_retries:   2,          # 0 disables retrying entirely
  backoff_base:  0.5
)
```

## Subscribers

```ruby
# Create or update. The API returns 200 for both and never says which, so this
# cannot tell you whether the subscriber was new.
subscriber = client.subscribers.upsert(
  email:         "ada@example.com",
  first_name:    "Ada",
  segment_ids:   ["seg_123"],       # max 50
  custom_fields: { "tier" => "gold" },
  double_optin:  true               # only honored on creation
)

subscriber.email           # => "ada@example.com"
subscriber.status          # => :active
subscriber.active?         # => true
subscriber.segments.first.name
subscriber.to_h            # the raw payload, always available

client.subscribers.retrieve("ada@example.com")   # id or email
client.subscribers.add_to_segments("sub_1", ["seg_123"])
client.subscribers.remove_from_segments("sub_1", ["seg_123"])
client.subscribers.unsubscribe("sub_1")
```

Custom field values are typed `string` throughout the API, so non-string values are coerced (`42` → `"42"`, `true` → `"true"`). `nil` is preserved, because it means "clear this field" rather than "set it to empty".

### Batch upsert

Up to 50 records per request, at 20 requests/minute — an effective ceiling of 1,000 upserts/minute.

The API returns `200` carrying **both** `successes` and `failures`, so `batch_upsert` raises on partial failure by default. The error carries the whole result, so successful records are never lost:

```ruby
begin
  client.subscribers.batch_upsert([
    { email: "ada@example.com" },
    { email: "not-an-email" }
  ])
rescue Flodesk::PartialFailureError => e
  e.result.successes            # => [Subscriber]
  e.result.failures.first.code  # => "invalid_email"
  e.result.failures.first.index # => 1, the position in your input
  e.result.failed_emails        # ready to retry
end
```

Prefer to inspect rather than rescue? Opt out explicitly:

```ruby
result = client.subscribers.batch_upsert(rows, raise_on_failure: false)
result.success?   # => false
result.failures
```

## Listing and pagination

`list` issues exactly one request and returns a `Page`:

```ruby
page = client.subscribers.list(page: 2, per_page: 100, status: :active)

page.items          # => [Subscriber]
page.total_items
page.more_pages?
page.each { |s| ... }   # this page only — no further requests
```

To walk everything, opt in explicitly. This is *not* the behavior of `each`, because traversing a large list can consume your entire 100 requests/minute budget — a cost that should be visible at the call site:

```ruby
client.subscribers.auto_paging_each do |subscriber|
  # ...
end

# Lazy: fetches only what it needs.
client.subscribers.auto_paging_each.first(10)
```

## Segments, custom fields, workflows

```ruby
client.segments.list
client.segments.retrieve("seg_123")
client.segments.create(name: "VIPs", color: "#ffeecc")
client.segments.colors

client.custom_fields.list          # paginated
client.custom_fields.list_all      # every field, unpaginated
client.custom_fields.create(label: "Favorite colour")

client.workflows.list(statuses: [:active, :paused])
client.workflows.add_subscriber("wf_123", email: "ada@example.com")
client.workflows.remove_subscriber("wf_123", "ada@example.com")
```

## Campaigns

```ruby
client.campaigns.list(search: "spring", status: :draft, order_by: "created_at")
```

> **Maturity caveat.** The Canva campaign endpoints (`publish_canva`, `canva_design_state`) cannot be safely exercised against a live account during development, so they are covered only by specification-derived stubs and are less battle-tested than the subscriber and segment operations.

> **`publish_canva` is never retried** — not on `5xx`, not on a timeout, not even on `429`. It publishes an email campaign, and no response code proves the campaign was *not* accepted. A retry could send it to your entire list a second time, which is unrecoverable and visible to every recipient. Failures are surfaced for a human to decide.

## Errors

Everything descends from `Flodesk::Error`, so you can rescue broadly or narrowly:

```ruby
begin
  client.subscribers.retrieve("nope")
rescue Flodesk::NotFoundError => e
  e.status    # => 404
  e.code      # => "not_found"
  e.message
  e.raw_body  # for debugging an unexpected shape
end
```

| Class | Cause |
| --- | --- |
| `Flodesk::BadRequestError` | `400` — your payload was rejected. Never retried |
| `Flodesk::AuthenticationError` | `401`/`403` |
| `Flodesk::NotFoundError` | `404` |
| `Flodesk::RateLimitError` | `429` |
| `Flodesk::ServerError` | `5xx` |
| `Flodesk::TimeoutError` | connect or read timeout |
| `Flodesk::ConnectionError` | the request never completed |
| `Flodesk::PartialFailureError` | a batch reported per-record failures |

The API declares no error-body schema anywhere; the `{code, message}` envelope this gem parses was established by probing the live API. Parsing therefore degrades gracefully — an HTML body from an edge proxy still raises a typed error carrying the raw response.

## Rate limits and retries

| Endpoint | Limit |
| --- | --- |
| Everything (default) | 100 requests/minute |
| `POST /subscribers/batch` | 20 requests/minute (≤50 subscribers each) |

Flodesk returns `X-Fd-RateLimit-Limit` and `X-Fd-RateLimit-Remaining` but **no reset header**, so there is no correct wait time to compute. Backoff is exponential with jitter, capped at 60 seconds, and is a documented heuristic — **this gem does not promise to keep you within quota.** Check the observed state if you need to pace a bulk job yourself:

```ruby
client.rate_limit&.remaining   # => 68
```

(Rate-limit state is per-thread, since a shared frozen client cannot hold mutable state.)

Which operations get retried:

| Safe to retry | Never retried |
| --- | --- |
| `POST /subscribers` (upsert) | `POST /segments` (creates) |
| `POST /subscribers/batch` (upsert) | `POST /custom-fields` (creates) |
| `POST .../segments` (idempotent add) | `POST /webhooks` (creates) |
| `POST .../unsubscribe` (terminal state) | `POST /campaigns/canva` (**publishes**) |
| `POST /workflows/.../subscribers` | |
| every `GET`, `PUT`, `DELETE` | |

## Webhooks

> **Flodesk does not sign webhooks.** The API description declares `security: []` on all three events — there is no signature header to verify. Anyone who learns your callback URL can forge a `subscriber.created` event.

Because of that, **verification is mandatory**: constructing a handler without choosing a strategy raises rather than defaulting to trust.

### Strategy 1 — token in the callback path

Cheap, no extra API call.

```ruby
# One-time: generate and store a token, then register the webhook.
token = Flodesk::Webhooks::Handler.generate_token

client.webhooks.create(
  name:     "My app",
  post_url: "https://app.example.com/flodesk/#{token}",
  events:   ["subscriber.created"]
)
```

```ruby
# config/routes.rb
post "/flodesk/:token", to: "flodesk_webhooks#create"

class FlodeskWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  HANDLER = Flodesk::Webhooks::Handler.new(
    token: Rails.application.credentials.flodesk_webhook_token
  )

  def create
    status, _headers, body = HANDLER.respond(
      body:     request.raw_post,
      token:    params[:token],
      on_error: ->(e) { Rails.logger.error("flodesk webhook failed: #{e.class}") }
    ) do |event|
      SyncSubscriberJob.perform_later(event.subscriber.id) unless seen?(event.dedupe_key)
    end

    render plain: body.join, status: status
  end
end
```

⚠️ **The token appears in your logs.** It is a path segment, so it lands in Rails request logs and your web server's access logs. Filter or silence that route before deploying, or use strategy 2 if you'd rather not put a secret in a URL at all.

### Strategy 2 — re-fetch (strongest)

Treats the payload as an untrusted *hint*: takes only the subscriber id and reads the authoritative record back from the API. Forgery-proof, but costs one API call per event against your 100/minute budget.

```ruby
HANDLER = Flodesk::Webhooks::Handler.new(verify: :refetch, client: FLODESK)

event = HANDLER.call(body: request.raw_post)
event.subscriber.email   # from the API, not from the payload
```

IP allowlisting is not an option — Flodesk publishes no ranges.

### Replay protection is yours

The event schemas define **no unique event id**, so the gem exposes a composed, SHA-256 dedupe key and leaves storage to you — only your app has a database:

```ruby
event.dedupe_key   # stable across identical deliveries
event.known?       # false for an event name the gem doesn't recognize yet
event.to_h         # raw payload, so a new Flodesk event stays usable
```

Respond with any 2xx to acknowledge. `#respond` maps failures to non-2xx (401 unverified, 400 unparseable, 500 if your block raises) so Flodesk retries rather than considering the event delivered.

### PII in webhook payloads

Events embed `email` **and** `optin_ip`. The gem never logs payload contents, redacts sensitive fields from instrumentation, and keeps PII out of `Event#inspect` — but what your own handler logs is up to you.

## Instrumentation

When ActiveSupport is present, every request attempt emits `flodesk.request`:

```ruby
ActiveSupport::Notifications.subscribe("flodesk.request") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  event.payload
  # => { method: "GET", endpoint: "/subscribers/[REDACTED]", status: 200,
  #      duration: 0.08, attempt: 1, rate_limit_remaining: 68 }
end
```

One event per *attempt*, so retries are visible. Payloads carry no request body, no response body, no API key, and any email embedded in a path is redacted.

## Testing

```ruby
require "flodesk/test_helpers"

RSpec.configure { |c| c.include Flodesk::TestHelpers }

stub_flodesk_upsert(email: "ada@example.com")
stub_flodesk_error(:get, "/subscribers/nope", status: 404)
stub_flodesk_batch(failures: [flodesk_batch_failure(index: 1)])
```

Fixture payloads follow the API description rather than whatever your code expects, so a stub can't drift into hiding a broken integration.

## What this gem does not do

- **OAuth2 / partner integrations.** API-key auth only. The OAuth2 flow needs token storage, expiry, and single-use refresh-token rotation whose concurrent-refresh race requires locking — a subsystem, not a feature. An auth seam is in place so it can be added without a breaking change.
- **ActiveRecord-style persistence.** No `save!`, dirty tracking, or lazy associations. `POST /subscribers` is upsert-only and never reports create-vs-update, so those semantics would be fiction, and lazy associations would hide N+1 HTTP calls.
- **Code generation.** The OpenAPI description is vendored as a *test oracle* instead: the suite asserts every documented operation has a client method, that declared parameters are sent, and that every documented status maps to an error class. Dropping in a newer spec fails the build when Flodesk adds an endpoint.

## Development

```bash
bin/setup
bundle exec rspec
bundle exec rubocop
bundle exec rbs -I sig validate
```

## Contributing

Bug reports and pull requests are welcome at <https://github.com/jimiray/flodesk-rb>.

## License

Available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
