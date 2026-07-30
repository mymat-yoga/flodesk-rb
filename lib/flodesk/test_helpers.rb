# frozen_string_literal: true

require "json"
require "webmock"

module Flodesk
  # WebMock stubs and fixture payloads for testing Flodesk integrations.
  #
  # Opt-in: nothing here is loaded by `require "flodesk"`.
  #
  #   require "flodesk/test_helpers"
  #
  #   RSpec.configure { |c| c.include Flodesk::TestHelpers }
  #
  #   stub_flodesk_upsert(email: "a@b.com")
  #   stub_flodesk_error(:post, "/subscribers", status: 404)
  #
  # Payload shapes follow the API description, so a stub cannot drift toward
  # whatever the calling code happens to expect — the classic way a green suite
  # hides a broken integration.
  module TestHelpers
    BASE_URL = Flodesk::DEFAULT_BASE_URL

    # A `SubscriberRes` payload with every documented field populated.
    def flodesk_subscriber(overrides = {})
      {
        "id" => "sub_test_1",
        "status" => "active",
        "email" => "subscriber@example.com",
        "source" => "manual",
        "first_name" => "Test",
        "last_name" => "Subscriber",
        "segments" => [],
        "custom_fields" => {},
        "optin_ip" => "203.0.113.1",
        "optin_timestamp" => "2024-01-01T00:00:00.000Z",
        "created_at" => "2024-01-01T00:00:00.000Z"
      }.merge(stringify(overrides))
    end

    # A `SegmentRes` payload.
    def flodesk_segment(overrides = {})
      {
        "id" => "seg_test_1",
        "name" => "Test Segment",
        "color" => "#ffeecc",
        "total_active_subscribers" => 0,
        "created_at" => "2024-01-01T00:00:00.000Z"
      }.merge(stringify(overrides))
    end

    # A `WebhookRes` payload.
    def flodesk_webhook(overrides = {})
      {
        "id" => "wh_test_1",
        "post_url" => "https://example.com/flodesk",
        "events" => ["subscriber.created"],
        "created_at" => "2024-01-01T00:00:00.000Z"
      }.merge(stringify(overrides))
    end

    # A paginated list envelope, with `meta` shaped as the API returns it.
    def flodesk_list(items, page: 1, per_page: 20, total_pages: 1, total_items: nil)
      {
        "meta" => {
          "page" => page, "per_page" => per_page,
          "total_pages" => total_pages, "total_items" => total_items || items.size
        },
        "data" => items
      }
    end

    # Stubs a successful subscriber upsert.
    def stub_flodesk_upsert(email: "subscriber@example.com", **overrides)
      stub_flodesk(:post, "/subscribers",
                   response: flodesk_subscriber(email: email, **overrides))
    end

    # Stubs a subscriber retrieval by id or email.
    def stub_flodesk_retrieve(id_or_email, **overrides)
      stub_flodesk(
        :get, "/subscribers/#{encode(id_or_email)}",
        response: flodesk_subscriber(id: id_or_email.to_s, **overrides)
      )
    end

    # Stubs a subscriber list.
    def stub_flodesk_list_subscribers(subscribers = [flodesk_subscriber], **pagination)
      stub_flodesk(:get, "/subscribers", response: flodesk_list(subscribers, **pagination))
    end

    # Stubs a batch upsert.
    #
    # Pass `failures:` to exercise partial failure, which is the case worth
    # testing: the API reports it inside a 200, and by default the gem raises
    # {Flodesk::PartialFailureError} for it.
    def stub_flodesk_batch(successes: [flodesk_subscriber], failures: [])
      stub_flodesk(
        :post, "/subscribers/batch",
        response: { "successes" => successes, "failures" => failures }
      )
    end

    # A `BatchItemError` payload.
    def flodesk_batch_failure(index: 0, code: "invalid_email", **overrides)
      {
        "index" => index,
        "email" => "bad@",
        "id" => nil,
        "code" => code,
        "message" => "Email is invalid"
      }.merge(stringify(overrides))
    end

    # Stubs an error response using the live API's `{code, message}` envelope.
    def stub_flodesk_error(method, path, status:, code: nil, message: nil)
      stub_flodesk(
        method, path, status: status,
                      response: { "code" => code || "error", "message" => message || "Request failed" }
      )
    end

    # Stubs a rate-limited response, including the headers the API sends. There
    # is deliberately no reset header, because the API does not send one.
    def stub_flodesk_rate_limited(method, path, limit: 100)
      stub_flodesk(
        method, path, status: 429,
                      response: { "code" => "rate_limited", "message" => "Too many requests" },
                      headers: { "X-Fd-RateLimit-Limit" => limit.to_s, "X-Fd-RateLimit-Remaining" => "0" }
      )
    end

    # The general-purpose stub the helpers above are built on.
    def stub_flodesk(method, path, response: nil, status: 200, headers: {}, base_url: BASE_URL)
      WebMock::API.stub_request(method, "#{base_url}#{path}").to_return(
        status: status,
        body: response.nil? ? "" : JSON.generate(response),
        headers: { "Content-Type" => "application/json" }.merge(headers)
      )
    end

    private

    def stringify(hash)
      hash.to_h { |k, v| [k.to_s, v] }
    end

    def encode(value)
      value.to_s.b.gsub(/[^A-Za-z0-9\-._~]/n) { |c| format("%%%02X", c.ord) }
    end
  end
end
